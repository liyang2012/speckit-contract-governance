#!/usr/bin/env python3
"""Semantic contract governance helpers shared by Bash and PowerShell wrappers."""

from __future__ import annotations

import argparse
import dataclasses
import datetime as dt
import json
import re
import subprocess
import sys
from pathlib import Path
from typing import Any, Iterable

try:
    import yaml
except ImportError as exc:  # pragma: no cover - exercised by wrapper preflight
    raise SystemExit(
        "contract-governance: PyYAML is required for semantic validation; "
        "install it with `python3 -m pip install pyyaml`."
    ) from exc


HTTP_METHODS = {"get", "post", "put", "delete", "patch", "options", "head", "trace"}
DEFAULT_INTERNAL_HTTP_TAG = "内部API"
DEFAULT_ALLOWED_TAGS = ["前端API", "Feign", DEFAULT_INTERNAL_HTTP_TAG, "外部API"]
DEFAULT_INTERNAL_SERVICE_AUTH_MODE = "provider-defined"
VALID_INTERNAL_SERVICE_AUTH_MODES = {"provider-defined", "network-only"}
DEFAULT_STATUSES = ["PENDING", "RESOLVED", "MISMATCH"]
DEFAULT_ACKS = ["PENDING_ACK", "ACKNOWLEDGED"]


@dataclasses.dataclass
class Finding:
    severity: str
    code: str
    message: str
    file: str = ""
    pointer: str = ""
    data: dict[str, Any] = dataclasses.field(default_factory=dict)

    def as_dict(self) -> dict[str, Any]:
        return dataclasses.asdict(self)


@dataclasses.dataclass
class Operation:
    service: str
    path: str
    method: str
    operation_id: str
    tags: list[str]
    raw: dict[str, Any]
    document: dict[str, Any]
    file: Path

    @property
    def key(self) -> str:
        return f"{self.method.upper()} {self.path}"


@dataclasses.dataclass
class Change:
    change_type: str
    code: str
    method: str
    path: str
    operation_id: str
    description: str
    consumers: list[str] = dataclasses.field(default_factory=list)

    def as_dict(self) -> dict[str, Any]:
        return dataclasses.asdict(self)


def load_yaml(path: Path) -> Any:
    with path.open("r", encoding="utf-8") as handle:
        return yaml.safe_load(handle) or {}


def load_yaml_text(text: str) -> Any:
    return yaml.safe_load(text) or {}


def repo_relative(path: Path, root: Path) -> str:
    try:
        return str(path.resolve().relative_to(root.resolve()))
    except ValueError:
        return str(path)


def config_defaults(root: Path) -> tuple[dict[str, Any], dict[str, Any]]:
    config_path = root / ".specify/extensions/contract-governance/contract-governance-config.yml"
    if config_path.exists():
        config = load_yaml(config_path)
    else:
        extension_path = root / ".specify/extensions/contract-governance/extension.yml"
        extension = load_yaml(extension_path) if extension_path.exists() else {}
        config = extension.get("config", {}) if isinstance(extension, dict) else {}
    defaults = config.get("defaults", config) if isinstance(config, dict) else {}
    return defaults if isinstance(defaults, dict) else {}, config if isinstance(config, dict) else {}


def resolve_ref(document: dict[str, Any], value: Any) -> Any:
    if not isinstance(value, dict) or "$ref" not in value:
        return value
    ref = value.get("$ref", "")
    if not isinstance(ref, str) or not ref.startswith("#/"):
        return value
    current: Any = document
    for token in ref[2:].split("/"):
        token = token.replace("~1", "/").replace("~0", "~")
        if not isinstance(current, dict) or token not in current:
            return value
        current = current[token]
    return current


def iter_operations(document: dict[str, Any], service: str, file: Path) -> Iterable[Operation]:
    paths = document.get("paths", {})
    if not isinstance(paths, dict):
        return
    for path, path_item in paths.items():
        if not isinstance(path_item, dict):
            continue
        for method, raw in path_item.items():
            if str(method).lower() not in HTTP_METHODS or not isinstance(raw, dict):
                continue
            tags = raw.get("tags", [])
            if isinstance(tags, str):
                tags = [tags]
            if not isinstance(tags, list):
                tags = []
            yield Operation(
                service=service,
                path=str(path),
                method=str(method).lower(),
                operation_id=str(raw.get("operationId", "") or ""),
                tags=[str(tag) for tag in tags],
                raw=raw,
                document=document,
                file=file,
            )


def operation_indexes(document: dict[str, Any], service: str, file: Path) -> tuple[dict[str, Operation], dict[str, Operation]]:
    by_key: dict[str, Operation] = {}
    by_id: dict[str, Operation] = {}
    for operation in iter_operations(document, service, file):
        by_key[operation.key] = operation
        if operation.operation_id:
            by_id[operation.operation_id] = operation
    return by_key, by_id


def success_schema(operation: Operation) -> Any:
    responses = operation.raw.get("responses", {})
    if not isinstance(responses, dict):
        return None
    success_keys = sorted(str(key) for key in responses if str(key).startswith("2"))
    for key in success_keys:
        response = responses.get(key, responses.get(int(key) if key.isdigit() else key, {}))
        response = resolve_ref(operation.document, response)
        if not isinstance(response, dict):
            continue
        content = response.get("content", {})
        if not isinstance(content, dict):
            continue
        media = content.get("application/json")
        if media is None and content:
            media = next(iter(content.values()))
        if isinstance(media, dict) and media.get("schema") is not None:
            return media["schema"]
    return None


def schema_property_names(document: dict[str, Any], schema: Any, seen: set[int] | None = None) -> set[str]:
    seen = seen or set()
    schema = resolve_ref(document, schema)
    if not isinstance(schema, dict):
        return set()
    marker = id(schema)
    if marker in seen:
        return set()
    seen.add(marker)
    names: set[str] = set()
    properties = schema.get("properties", {})
    if isinstance(properties, dict):
        names.update(str(name) for name in properties)
        for child in properties.values():
            names.update(schema_property_names(document, child, seen))
    for key in ("allOf", "oneOf", "anyOf"):
        values = schema.get(key, [])
        if isinstance(values, list):
            for child in values:
                names.update(schema_property_names(document, child, seen))
    if schema.get("items") is not None:
        names.update(schema_property_names(document, schema["items"], seen))
    additional = schema.get("additionalProperties")
    if isinstance(additional, dict):
        names.update(schema_property_names(document, additional, seen))
    return names


def schema_has_path(document: dict[str, Any], schema: Any, dotted_path: str) -> bool:
    parts = [part for part in dotted_path.split(".") if part]
    if not parts:
        return True
    if len(parts) == 1:
        return parts[0] in schema_property_names(document, schema)

    def descend(current: Any, remaining: list[str], seen_refs: set[str]) -> bool:
        if isinstance(current, dict) and "$ref" in current:
            ref = str(current["$ref"])
            if ref in seen_refs:
                return False
            seen_refs = set(seen_refs)
            seen_refs.add(ref)
            current = resolve_ref(document, current)
        if not isinstance(current, dict):
            return False
        for key in ("allOf", "oneOf", "anyOf"):
            values = current.get(key, [])
            if isinstance(values, list) and any(descend(value, remaining, seen_refs) for value in values):
                return True
        if current.get("type") == "array" or "items" in current:
            return descend(current.get("items"), remaining, seen_refs)
        properties = current.get("properties", {})
        if not isinstance(properties, dict) or remaining[0] not in properties:
            return False
        if len(remaining) == 1:
            return True
        return descend(properties[remaining[0]], remaining[1:], seen_refs)

    return descend(schema, parts, set())


def flatten_schema(document: dict[str, Any], schema: Any) -> dict[str, dict[str, Any]]:
    result: dict[str, dict[str, Any]] = {}

    def walk(current: Any, prefix: str, required: bool, seen_refs: set[str]) -> None:
        if isinstance(current, dict) and "$ref" in current:
            ref = str(current["$ref"])
            if ref in seen_refs:
                return
            seen_refs = set(seen_refs)
            seen_refs.add(ref)
            current = resolve_ref(document, current)
        if not isinstance(current, dict):
            return
        for key in ("allOf", "oneOf", "anyOf"):
            values = current.get(key, [])
            if isinstance(values, list):
                for child in values:
                    walk(child, prefix, required, seen_refs)
        if current.get("type") == "array" or "items" in current:
            walk(current.get("items"), f"{prefix}[]" if prefix else "[]", required, seen_refs)
        properties = current.get("properties", {})
        required_names = set(current.get("required", []) or [])
        if not isinstance(properties, dict):
            return
        for name, child in properties.items():
            path = f"{prefix}.{name}" if prefix else str(name)
            resolved = resolve_ref(document, child)
            value = resolved if isinstance(resolved, dict) else {}
            result[path] = {
                "type": value.get("type", "object" if value.get("properties") else ""),
                "format": value.get("format", ""),
                "required": bool(required or name in required_names),
                "enum": list(value.get("enum", []) or []),
            }
            walk(child, path, bool(required or name in required_names), seen_refs)

    walk(schema, "", False, set())
    return result


def parse_date(value: Any) -> dt.date | None:
    if isinstance(value, dt.datetime):
        return value.date()
    if isinstance(value, dt.date):
        return value
    if not value:
        return None
    try:
        return dt.date.fromisoformat(str(value)[:10])
    except ValueError:
        return None


def load_project(root: Path, service_filter: str = "") -> tuple[dict[str, dict[str, Any]], dict[str, dict[str, Operation]], list[Finding]]:
    contracts = root / "contracts"
    documents: dict[str, dict[str, Any]] = {}
    operations: dict[str, dict[str, Operation]] = {}
    findings: list[Finding] = []
    for registry_file in sorted((contracts / "_registry").glob("*.yaml")):
        service = registry_file.stem
        if service_filter and service != service_filter:
            continue
        try:
            registry = load_yaml(registry_file)
        except Exception as exc:  # noqa: BLE001
            findings.append(Finding("error", "yaml-invalid", f"无法解析 registry：{exc}", str(registry_file)))
            continue
        api_rel = ((registry.get("contract_files") or {}).get("api") if isinstance(registry, dict) else None)
        api_file = contracts / str(api_rel or f"{service}/api.yaml")
        if not api_file.exists():
            findings.append(Finding("error", "provider-api-missing", f"Provider API 不存在：{api_file}", str(registry_file)))
            continue
        try:
            document = load_yaml(api_file)
        except Exception as exc:  # noqa: BLE001
            findings.append(Finding("error", "yaml-invalid", f"无法解析 OpenAPI：{exc}", str(api_file)))
            continue
        documents[service] = document
        _, by_id = operation_indexes(document, service, api_file)
        operations[service] = by_id
    return documents, operations, findings


def map_entries(service_map: Path) -> tuple[set[str], set[str]]:
    providers: set[str] = set()
    consumers: set[str] = set()
    if not service_map.exists():
        return providers, consumers
    text = service_map.read_text(encoding="utf-8")
    providers.update(re.findall(r"contracts/([A-Za-z0-9_.-]+)/api\.yaml", text))
    providers.update(re.findall(r"_registry/([A-Za-z0-9_.-]+)\.ya?ml", text))
    consumers.update(re.findall(r"contracts/_consumers/([A-Za-z0-9_.-]+)\.ya?ml", text))
    return providers, consumers


def map_details(service_map: Path) -> tuple[dict[str, dict[str, str]], set[tuple[str, str, str]]]:
    providers: dict[str, dict[str, str]] = {}
    dependencies: set[tuple[str, str, str]] = set()
    if not service_map.exists():
        return providers, dependencies
    text = service_map.read_text(encoding="utf-8")
    for line in text.splitlines():
        match = re.search(r"contracts/([A-Za-z0-9_.-]+)/api\.yaml", line)
        if match and line.strip().startswith("|"):
            cells = [cell.strip().strip("`") for cell in line.strip().strip("|").split("|")]
            if len(cells) >= 4:
                providers[match.group(1)] = {"database": cells[1], "contract": cells[2], "status": cells[3]}
        dependency = re.search(r"([A-Za-z0-9_.-]+)\s*→\s*([A-Za-z0-9_.-]+)\s*\((Feign|HTTP|MQ)", line)
        if dependency:
            dependencies.add((dependency.group(1), dependency.group(2), dependency.group(3)))
    return providers, dependencies


def validate_semantics(root: Path, service_filter: str = "", consumer_filter: str = "") -> list[Finding]:
    defaults, _ = config_defaults(root)
    allowed_tags = [str(value) for value in defaults.get("allowed_tags", DEFAULT_ALLOWED_TAGS)]
    internal_prefix = str(defaults.get("internal_path_prefix", "/internal/"))
    internal_http_tag = str(defaults.get("internal_http_tag", DEFAULT_INTERNAL_HTTP_TAG))
    internal_service_auth_mode = str(
        defaults.get("internal_service_auth_mode", DEFAULT_INTERNAL_SERVICE_AUTH_MODE)
    ).strip().lower()
    statuses = [str(value) for value in defaults.get("consumer_statuses", DEFAULT_STATUSES)]
    ack_values = [str(value) for value in defaults.get("change_ack_values", DEFAULT_ACKS)]
    pending_max_age_value = defaults.get("pending_max_age_days", 30)
    pending_max_age = 30 if pending_max_age_value is None else int(pending_max_age_value)
    contracts = root / "contracts"
    documents, operations, findings = load_project(root, service_filter)
    if internal_service_auth_mode not in VALID_INTERNAL_SERVICE_AUTH_MODES:
        findings.append(
            Finding(
                "error",
                "internal-service-auth-mode-invalid",
                "internal_service_auth_mode 必须是 provider-defined 或 network-only，"
                f"当前值为 {internal_service_auth_mode or '<empty>'}",
                ".specify/extensions/contract-governance/contract-governance-config.yml",
                "defaults.internal_service_auth_mode",
            )
        )

    registry_services = {path.stem for path in (contracts / "_registry").glob("*.yaml")}
    consumer_names = {path.stem for path in (contracts / "_consumers").glob("*.yaml")}
    map_providers, map_consumers = map_entries(contracts / "SERVICE-MAP.md")
    map_provider_details, map_dependencies = map_details(contracts / "SERVICE-MAP.md")
    for missing in sorted(registry_services - map_providers):
        findings.append(Finding("error", "service-map-provider-missing", f"SERVICE-MAP 缺少 Provider：{missing}", "contracts/SERVICE-MAP.md"))
    for missing in sorted(consumer_names - map_consumers):
        findings.append(Finding("error", "service-map-consumer-missing", f"SERVICE-MAP 缺少 Consumer：{missing}", "contracts/SERVICE-MAP.md"))
    for stale in sorted(map_providers - registry_services):
        findings.append(Finding("warning", "service-map-provider-stale", f"SERVICE-MAP 存在未注册 Provider：{stale}", "contracts/SERVICE-MAP.md"))
    for stale in sorted(map_consumers - consumer_names):
        findings.append(Finding("warning", "service-map-consumer-stale", f"SERVICE-MAP 存在无文件 Consumer：{stale}", "contracts/SERVICE-MAP.md"))

    _, config = config_defaults(root)
    service_meta = {
        str(item.get("name")): item
        for item in (config.get("services", []) if isinstance(config, dict) else [])
        if isinstance(item, dict) and item.get("name")
    }
    derived_dependencies: set[tuple[str, str, str]] = set()
    for registry_file in sorted((contracts / "_registry").glob("*.yaml")):
        try:
            registry = load_yaml(registry_file)
        except Exception:
            continue
        service = str(registry.get("service") or registry_file.stem)
        if not service_filter or service == service_filter:
            for derived_key, source in (
                ("feign_operations", "Provider Feign operation 应从 contract_files.api 的 tags: [Feign] 推导"),
                ("http_operations", f"Provider 内部 HTTP operation 应从 contract_files.api 的 tags: [{internal_http_tag}] 推导"),
                ("mq_operations", "Provider 事件应从 contract_files.events 推导"),
            ):
                if derived_key in registry:
                    findings.append(
                        Finding(
                            "error",
                            "registry-derived-summary-forbidden",
                            f"{service} registry 不得维护重复字段 {derived_key}；{source}，调用方从各 Consumer registry 的 consumes 推导",
                            repo_relative(registry_file, root),
                            derived_key,
                        )
                    )
        details = map_provider_details.get(service, {})
        expected_database = str(registry.get("database") or service_meta.get(service, {}).get("database") or "")
        expected_status = str(service_meta.get(service, {}).get("status") or "")
        if details and expected_database and details.get("database") != expected_database:
            findings.append(Finding("warning", "service-map-database-drift", f"{service} 的 SERVICE-MAP database={details.get('database')}，registry/config={expected_database}", "contracts/SERVICE-MAP.md"))
        if details and expected_status and details.get("status") != expected_status:
            findings.append(Finding("warning", "service-map-status-drift", f"{service} 的 SERVICE-MAP status={details.get('status')}，配置={expected_status}", "contracts/SERVICE-MAP.md"))
        consumes = registry.get("consumes") or {}
        for entry in consumes.get("feign", []) or []:
            if isinstance(entry, dict):
                provider = entry.get("service") or entry.get("provider")
                if provider:
                    derived_dependencies.add((service, str(provider), "Feign"))
        for entry in consumes.get("http", []) or []:
            if isinstance(entry, dict):
                provider = entry.get("service") or entry.get("provider")
                if provider:
                    derived_dependencies.add((service, str(provider), "HTTP"))
        for entry in consumes.get("mq", []) or []:
            if isinstance(entry, dict):
                publisher = entry.get("publisher") or entry.get("service")
                if publisher:
                    derived_dependencies.add((service, str(publisher), "MQ"))
    for consumer_service, provider, protocol in sorted(derived_dependencies - map_dependencies):
        findings.append(Finding("error", "service-map-dependency-missing", f"SERVICE-MAP 缺少依赖：{consumer_service} → {provider} ({protocol})", "contracts/SERVICE-MAP.md"))
    for consumer_service, provider, protocol in sorted(map_dependencies - derived_dependencies):
        findings.append(Finding("warning", "service-map-dependency-stale", f"SERVICE-MAP 存在 registry 未登记依赖：{consumer_service} → {provider} ({protocol})", "contracts/SERVICE-MAP.md"))

    for service, document in documents.items():
        api_file = contracts / service / "api.yaml"
        seen_ids: set[str] = set()
        for operation in iter_operations(document, service, api_file):
            pointer = f"{operation.method.upper()} {operation.path}"
            if not operation.operation_id:
                findings.append(Finding("error", "operation-id-missing", f"{service} {pointer} 缺少 operationId", repo_relative(api_file, root), pointer))
            elif operation.operation_id in seen_ids:
                findings.append(Finding("error", "operation-id-duplicate", f"{service} 重复 operationId：{operation.operation_id}", repo_relative(api_file, root), pointer))
            seen_ids.add(operation.operation_id)
            unknown = sorted(set(operation.tags) - set(allowed_tags))
            if unknown:
                findings.append(Finding("error", "operation-tag-invalid", f"{service}.{operation.operation_id} 使用未允许 tags：{', '.join(unknown)}", repo_relative(api_file, root), pointer))
            if "Feign" in operation.tags and internal_prefix not in operation.path:
                findings.append(Finding("error", "feign-path-invalid", f"{service}.{operation.operation_id} 是 Feign operation，但路径不包含 {internal_prefix}", repo_relative(api_file, root), pointer))
            if internal_http_tag in operation.tags and internal_prefix not in operation.path:
                findings.append(Finding("error", "internal-http-path-invalid", f"{service}.{operation.operation_id} 是 {internal_http_tag} operation，但路径不包含 {internal_prefix}", repo_relative(api_file, root), pointer))
            if (
                internal_service_auth_mode == "network-only"
                and ({"Feign", internal_http_tag} & set(operation.tags))
            ):
                security = (
                    operation.raw["security"]
                    if "security" in operation.raw
                    else operation.document.get("security")
                )
                if security not in (None, []):
                    findings.append(
                        Finding(
                            "error",
                            "internal-service-auth-forbidden",
                            f"{service}.{operation.operation_id} 是内网 operation；"
                            "internal_service_auth_mode=network-only 时不得声明或继承 security。"
                            "如 OpenAPI 顶层定义了认证，请在该 operation 显式设置 security: []",
                            repo_relative(api_file, root),
                            pointer,
                            {"security": security},
                        )
                    )

    today = dt.date.today()
    for consumer_file in sorted((contracts / "_consumers").glob("*.yaml")):
        if consumer_filter and consumer_file.stem != consumer_filter:
            continue
        try:
            consumer_data = load_yaml(consumer_file)
        except Exception as exc:  # noqa: BLE001
            findings.append(Finding("error", "yaml-invalid", f"无法解析 Consumer Contract：{exc}", repo_relative(consumer_file, root)))
            continue
        generated = parse_date(consumer_data.get("generated")) if isinstance(consumer_data, dict) else None
        entries = (((consumer_data.get("consumes") or {}).get("http")) if isinstance(consumer_data, dict) else []) or []
        if not isinstance(entries, list):
            findings.append(Finding("error", "consumer-http-invalid", "consumes.http 必须是数组", repo_relative(consumer_file, root)))
            continue
        for index, entry in enumerate(entries):
            if not isinstance(entry, dict):
                findings.append(Finding("error", "consumer-entry-invalid", f"第 {index + 1} 个 HTTP 消费项不是对象", repo_relative(consumer_file, root)))
                continue
            provider = str(entry.get("provider", "") or "")
            operation_id = str(entry.get("operationId", "") or "")
            status = str(entry.get("status", "") or "")
            pointer = f"consumes.http[{index}]"
            if status not in statuses:
                findings.append(Finding("error", "consumer-status-invalid", f"{provider}.{operation_id} 状态非法：{status}", repo_relative(consumer_file, root), pointer))
            operation = operations.get(provider, {}).get(operation_id)
            if operation is None:
                if status == "RESOLVED":
                    findings.append(Finding("error", "resolved-operation-missing", f"{provider}.{operation_id} 标记为 RESOLVED，但 Provider operation 不存在", repo_relative(consumer_file, root), pointer))
                continue
            if "Feign" in operation.tags:
                findings.append(Finding("error", "frontend-consumes-feign", f"前端不得消费 Feign operation：{provider}.{operation_id}", repo_relative(consumer_file, root), pointer))
            elif internal_http_tag in operation.tags:
                findings.append(Finding("error", "frontend-consumes-internal-http", f"前端不得消费 {internal_http_tag} operation：{provider}.{operation_id}", repo_relative(consumer_file, root), pointer))
            elif not set(operation.tags).intersection({"前端API", "外部API"}):
                findings.append(Finding("error", "frontend-tag-invalid", f"{provider}.{operation_id} 未标记为前端可消费 operation", repo_relative(consumer_file, root), pointer))

            fields = entry.get("required_fields", []) or []
            if isinstance(fields, str):
                fields = [fields]
            if not isinstance(fields, list):
                findings.append(Finding("error", "required-fields-invalid", f"{provider}.{operation_id} required_fields 必须是数组", repo_relative(consumer_file, root), pointer))
                fields = []
            schema = success_schema(operation)
            missing_fields = [str(field) for field in fields if not schema_has_path(operation.document, schema, str(field))]
            if missing_fields and status == "RESOLVED":
                findings.append(Finding("error", "resolved-required-fields-missing", f"{provider}.{operation_id} 已 RESOLVED，但响应缺少 required_fields：{', '.join(missing_fields)}", repo_relative(consumer_file, root), pointer, {"missing_fields": missing_fields}))
            elif missing_fields:
                findings.append(Finding("warning", "pending-schema-mismatch", f"{provider}.{operation_id} 已存在，但响应缺少 required_fields：{', '.join(missing_fields)}；应保持 PENDING 或记录 MISMATCH", repo_relative(consumer_file, root), pointer, {"missing_fields": missing_fields}))
            elif status == "PENDING":
                findings.append(Finding("warning", "pending-semantically-resolvable", f"{provider}.{operation_id} 的 operation、调用边界和 required_fields 均可解析，可进行业务语义确认", repo_relative(consumer_file, root), pointer))

            pending_since = parse_date(entry.get("since") or entry.get("created_at") or entry.get("created")) or generated
            if status == "PENDING" and pending_since:
                age = (today - pending_since).days
                if pending_max_age > 0 and age > pending_max_age:
                    findings.append(Finding("warning", "pending-stale", f"{provider}.{operation_id} 已 PENDING {age} 天，超过阈值 {pending_max_age} 天", repo_relative(consumer_file, root), pointer, {"age_days": age, "threshold_days": pending_max_age}))

            changes = entry.get("changes", []) or []
            if isinstance(changes, list):
                for change_index, change in enumerate(changes):
                    if not isinstance(change, dict):
                        continue
                    ack = str(change.get("ack", "") or "")
                    if ack not in ack_values:
                        findings.append(Finding("error", "change-ack-invalid", f"{provider}.{operation_id} change ack 非法：{ack}", repo_relative(consumer_file, root), f"{pointer}.changes[{change_index}]"))
                    elif change.get("type") == "breaking" and ack == "PENDING_ACK":
                        findings.append(Finding("warning", "breaking-change-unacknowledged", f"{provider}.{operation_id} 仍有未确认 breaking change：{change.get('change_id', '')}", repo_relative(consumer_file, root), f"{pointer}.changes[{change_index}]"))

    for registry_file in sorted((contracts / "_registry").glob("*.yaml")):
        consumer_service = registry_file.stem
        try:
            registry = load_yaml(registry_file)
        except Exception:
            continue
        feign_entries = (((registry.get("consumes") or {}).get("feign")) if isinstance(registry, dict) else []) or []
        if not isinstance(feign_entries, list):
            continue
        for index, entry in enumerate(feign_entries):
            if not isinstance(entry, dict):
                continue
            provider = str(entry.get("service") or entry.get("provider") or "")
            operation_id = str(entry.get("operationId") or "")
            status = str(entry.get("status") or "")
            operation = operations.get(provider, {}).get(operation_id)
            pointer = f"consumes.feign[{index}]"
            if operation is None and status == "RESOLVED":
                findings.append(Finding("error", "resolved-feign-operation-missing", f"{consumer_service} 将 {provider}.{operation_id} 标记为 RESOLVED，但 Provider operation 不存在", repo_relative(registry_file, root), pointer))
            elif operation is not None and "Feign" not in operation.tags:
                findings.append(Finding("error", "backend-consumes-non-feign", f"{consumer_service} 的 Feign 依赖 {provider}.{operation_id} 未使用 Feign tag", repo_relative(registry_file, root), pointer))
            elif operation is not None and status == "PENDING":
                findings.append(Finding("warning", "pending-feign-resolvable", f"{consumer_service} 的 Feign 依赖 {provider}.{operation_id} 已可解析，可进行语义确认", repo_relative(registry_file, root), pointer))

        http_entries = (((registry.get("consumes") or {}).get("http")) if isinstance(registry, dict) else []) or []
        if not isinstance(http_entries, list):
            findings.append(Finding("error", "backend-http-invalid", f"{consumer_service} 的 consumes.http 必须是数组", repo_relative(registry_file, root), "consumes.http"))
            http_entries = []
        for index, entry in enumerate(http_entries):
            if not isinstance(entry, dict):
                findings.append(Finding("error", "backend-http-entry-invalid", f"{consumer_service} 的第 {index + 1} 个 HTTP 消费项不是对象", repo_relative(registry_file, root), f"consumes.http[{index}]"))
                continue
            provider = str(entry.get("service") or entry.get("provider") or "")
            operation_id = str(entry.get("operationId") or "")
            status = str(entry.get("status") or "")
            operation = operations.get(provider, {}).get(operation_id)
            pointer = f"consumes.http[{index}]"
            if status not in statuses:
                findings.append(Finding("error", "backend-http-status-invalid", f"{consumer_service} 的 HTTP 依赖 {provider}.{operation_id} 状态非法：{status}", repo_relative(registry_file, root), pointer))
            if operation is None and status == "RESOLVED":
                findings.append(Finding("error", "resolved-http-operation-missing", f"{consumer_service} 将 {provider}.{operation_id} 标记为 RESOLVED，但 Provider operation 不存在", repo_relative(registry_file, root), pointer))
            elif operation is not None and internal_http_tag not in operation.tags:
                findings.append(Finding("error", "backend-consumes-non-internal-http", f"{consumer_service} 的 HTTP 依赖 {provider}.{operation_id} 未使用 {internal_http_tag} tag", repo_relative(registry_file, root), pointer))
            elif operation is not None and status == "PENDING":
                findings.append(Finding("warning", "pending-http-resolvable", f"{consumer_service} 的 HTTP 依赖 {provider}.{operation_id} 已可解析，可进行语义确认", repo_relative(registry_file, root), pointer))

        events = ((registry.get("contract_files") or {}).get("events")) if isinstance(registry, dict) else []
        if isinstance(events, list):
            for event in events:
                event_file = contracts / str(event)
                if not event_file.exists():
                    continue
                try:
                    event_data = load_yaml(event_file)
                except Exception as exc:  # noqa: BLE001
                    findings.append(Finding("error", "event-yaml-invalid", f"事件契约无法解析：{exc}", repo_relative(event_file, root)))
                    continue
                if not any(key in event_data for key in ("topic", "name", "event")):
                    findings.append(Finding("warning", "event-identity-missing", "事件契约缺少 topic/name/event 标识", repo_relative(event_file, root)))
                if not any(key in event_data for key in ("schema", "payload", "message", "properties")):
                    findings.append(Finding("warning", "event-schema-missing", "事件契约缺少 schema/payload/message 定义", repo_relative(event_file, root)))
                if "version" not in event_data:
                    findings.append(Finding("warning", "event-version-missing", "事件契约缺少 version", repo_relative(event_file, root)))

    return findings


def parameter_map(operation: Operation) -> dict[tuple[str, str], dict[str, Any]]:
    result: dict[tuple[str, str], dict[str, Any]] = {}
    parameters = operation.raw.get("parameters", []) or []
    if isinstance(parameters, list):
        for parameter in parameters:
            parameter = resolve_ref(operation.document, parameter)
            if isinstance(parameter, dict):
                result[(str(parameter.get("in", "")), str(parameter.get("name", "")))] = parameter
    return result


def compare_schema(old_document: dict[str, Any], old_schema: Any, new_document: dict[str, Any], new_schema: Any) -> list[tuple[str, str, str]]:
    changes: list[tuple[str, str, str]] = []
    old_fields = flatten_schema(old_document, old_schema)
    new_fields = flatten_schema(new_document, new_schema)
    for field in sorted(old_fields.keys() - new_fields.keys()):
        changes.append(("breaking", "response-field-removed", f"响应字段已删除：{field}"))
    for field in sorted(new_fields.keys() - old_fields.keys()):
        kind = "breaking" if new_fields[field].get("required") else "non-breaking"
        code = "required-response-field-added" if kind == "breaking" else "optional-response-field-added"
        changes.append((kind, code, f"响应字段已新增：{field}"))
    for field in sorted(old_fields.keys() & new_fields.keys()):
        old = old_fields[field]
        new = new_fields[field]
        if (old.get("type"), old.get("format")) != (new.get("type"), new.get("format")):
            changes.append(("breaking", "response-field-type-changed", f"响应字段类型变化：{field} {old.get('type')}/{old.get('format')} → {new.get('type')}/{new.get('format')}"))
        if not old.get("required") and new.get("required"):
            changes.append(("breaking", "response-field-required", f"响应字段变为必填：{field}"))
        old_enum = set(old.get("enum", []))
        new_enum = set(new.get("enum", []))
        if old_enum and new_enum and not old_enum.issubset(new_enum):
            changes.append(("breaking", "response-enum-narrowed", f"响应枚举值收窄：{field}"))
    return changes


def compare_operations(old: Operation, new: Operation) -> list[tuple[str, str, str]]:
    changes: list[tuple[str, str, str]] = []
    if old.operation_id != new.operation_id:
        changes.append(("breaking", "operation-id-changed", f"operationId 变化：{old.operation_id} → {new.operation_id}"))
    if set(old.tags) != set(new.tags):
        changes.append(("breaking", "operation-tags-changed", f"调用方 tags 变化：{old.tags} → {new.tags}"))
    old_params = parameter_map(old)
    new_params = parameter_map(new)
    for key in sorted(old_params.keys() - new_params.keys()):
        changes.append(("breaking", "request-parameter-removed", f"请求参数已删除：{key[0]} {key[1]}"))
    for key in sorted(new_params.keys() - old_params.keys()):
        parameter = new_params[key]
        kind = "breaking" if parameter.get("required") else "non-breaking"
        changes.append((kind, "required-request-parameter-added" if kind == "breaking" else "optional-request-parameter-added", f"请求参数已新增：{key[0]} {key[1]}"))
    for key in sorted(old_params.keys() & new_params.keys()):
        old_schema = resolve_ref(old.document, old_params[key].get("schema", {}))
        new_schema = resolve_ref(new.document, new_params[key].get("schema", {}))
        old_sig = (old_schema.get("type"), old_schema.get("format")) if isinstance(old_schema, dict) else (None, None)
        new_sig = (new_schema.get("type"), new_schema.get("format")) if isinstance(new_schema, dict) else (None, None)
        if old_sig != new_sig:
            changes.append(("breaking", "request-parameter-type-changed", f"请求参数类型变化：{key[0]} {key[1]} {old_sig} → {new_sig}"))
        if not old_params[key].get("required") and new_params[key].get("required"):
            changes.append(("breaking", "request-parameter-required", f"请求参数变为必填：{key[0]} {key[1]}"))

    old_body = old.raw.get("requestBody") or {}
    new_body = new.raw.get("requestBody") or {}
    old_body = resolve_ref(old.document, old_body)
    new_body = resolve_ref(new.document, new_body)
    if isinstance(old_body, dict) and isinstance(new_body, dict):
        if not old_body.get("required") and new_body.get("required"):
            changes.append(("breaking", "request-body-required", "requestBody 变为必填"))

    changes.extend(compare_schema(old.document, success_schema(old), new.document, success_schema(new)))
    old_responses = {str(key) for key in (old.raw.get("responses", {}) or {})}
    new_responses = {str(key) for key in (new.raw.get("responses", {}) or {})}
    for status in sorted(old_responses - new_responses):
        changes.append(("breaking", "response-status-removed", f"响应状态码已删除：{status}"))
    for status in sorted(new_responses - old_responses):
        changes.append(("non-breaking", "response-status-added", f"响应状态码已新增：{status}"))
    return changes


def consumer_impact(root: Path, service: str, operation_id: str) -> list[str]:
    if not operation_id:
        return []
    contracts = root / "contracts"
    impacted: set[str] = set()
    for path in (contracts / "_consumers").glob("*.yaml"):
        try:
            data = load_yaml(path)
        except Exception:
            continue
        entries = ((data.get("consumes") or {}).get("http") or []) if isinstance(data, dict) else []
        for entry in entries if isinstance(entries, list) else []:
            if isinstance(entry, dict) and entry.get("provider") == service and entry.get("operationId") == operation_id:
                impacted.add(f"frontend:{path.stem}")
    for path in (contracts / "_registry").glob("*.yaml"):
        try:
            data = load_yaml(path)
        except Exception:
            continue
        consumes = (data.get("consumes") or {}) if isinstance(data, dict) else {}
        for protocol in ("feign", "http"):
            entries = (consumes.get(protocol) or []) if isinstance(consumes, dict) else []
            for entry in entries if isinstance(entries, list) else []:
                provider = entry.get("service") or entry.get("provider") if isinstance(entry, dict) else ""
                if isinstance(entry, dict) and provider == service and entry.get("operationId") == operation_id:
                    impacted.add(f"backend:{path.stem}")
    return sorted(impacted)


def semantic_diff(old_document: dict[str, Any], new_document: dict[str, Any], service: str, root: Path | None = None) -> list[Change]:
    placeholder = Path(f"contracts/{service}/api.yaml")
    old_by_key, _ = operation_indexes(old_document, service, placeholder)
    new_by_key, _ = operation_indexes(new_document, service, placeholder)
    changes: list[Change] = []
    for key in sorted(old_by_key.keys() - new_by_key.keys()):
        old = old_by_key[key]
        changes.append(Change("breaking", "operation-removed", old.method, old.path, old.operation_id, "operation 已删除", consumer_impact(root, service, old.operation_id) if root else []))
    for key in sorted(new_by_key.keys() - old_by_key.keys()):
        new = new_by_key[key]
        changes.append(Change("non-breaking", "operation-added", new.method, new.path, new.operation_id, "新增 operation", []))
    for key in sorted(old_by_key.keys() & new_by_key.keys()):
        old = old_by_key[key]
        new = new_by_key[key]
        for kind, code, description in compare_operations(old, new):
            operation_id = new.operation_id or old.operation_id
            impacted = consumer_impact(root, service, old.operation_id or operation_id) if root and kind == "breaking" else []
            changes.append(Change(kind, code, new.method, new.path, operation_id, description, impacted))
    return changes


def git_old_document(root: Path, service: str, base: str) -> dict[str, Any] | None:
    ref = base or "HEAD"
    relative = f"contracts/{service}/api.yaml"
    completed = subprocess.run(
        ["git", "-C", str(root), "show", f"{ref}:{relative}"],
        check=False,
        capture_output=True,
        text=True,
    )
    if completed.returncode != 0 or not completed.stdout.strip():
        return None
    return load_yaml_text(completed.stdout)


def report_payload(findings: list[Finding]) -> dict[str, Any]:
    return {
        "summary": {
            "errors": sum(item.severity == "error" for item in findings),
            "warnings": sum(item.severity == "warning" for item in findings),
            "info": sum(item.severity == "info" for item in findings),
        },
        "findings": [item.as_dict() for item in findings],
    }


def sarif_payload(findings: list[Finding]) -> dict[str, Any]:
    rules: dict[str, dict[str, Any]] = {}
    results: list[dict[str, Any]] = []
    for item in findings:
        rules.setdefault(item.code, {"id": item.code, "shortDescription": {"text": item.code}})
        result: dict[str, Any] = {
            "ruleId": item.code,
            "level": "error" if item.severity == "error" else "warning" if item.severity == "warning" else "note",
            "message": {"text": item.message},
        }
        if item.file:
            result["locations"] = [{"physicalLocation": {"artifactLocation": {"uri": item.file}}}]
        results.append(result)
    return {
        "$schema": "https://json.schemastore.org/sarif-2.1.0.json",
        "version": "2.1.0",
        "runs": [{"tool": {"driver": {"name": "contract-governance", "rules": list(rules.values())}}, "results": results}],
    }


def emit_findings(findings: list[Finding], output_format: str) -> None:
    if output_format == "json":
        print(json.dumps(report_payload(findings), ensure_ascii=False, indent=2))
        return
    if output_format == "sarif":
        print(json.dumps(sarif_payload(findings), ensure_ascii=False, indent=2))
        return
    labels = {"error": "失败", "warning": "警告", "info": "提示"}
    for item in findings:
        location = f" ({item.file}{'#' + item.pointer if item.pointer else ''})" if item.file else ""
        print(f"[contract-semantic] {labels.get(item.severity, item.severity)} [{item.code}]：{item.message}{location}")


def emit_changes(changes: list[Change], output_format: str) -> None:
    if output_format == "json":
        payload = {
            "summary": {
                "breaking": sum(item.change_type == "breaking" for item in changes),
                "non_breaking": sum(item.change_type == "non-breaking" for item in changes),
            },
            "changes": [item.as_dict() for item in changes],
        }
        print(json.dumps(payload, ensure_ascii=False, indent=2))
        return
    if output_format == "sarif":
        findings = [
            Finding(
                "error" if item.change_type == "breaking" else "info",
                item.code,
                item.description + (f"；影响：{', '.join(item.consumers)}" if item.consumers else ""),
                item.path,
                f"{item.method.upper()} {item.path}" if item.method else item.path,
                {"change_type": item.change_type, "operation_id": item.operation_id, "consumers": item.consumers},
            )
            for item in changes
        ]
        print(json.dumps(sarif_payload(findings), ensure_ascii=False, indent=2))
        return
    if output_format == "tsv":
        for item in changes:
            values = [item.change_type, item.method, item.path, item.operation_id, item.code, item.description, ",".join(item.consumers)]
            print("\t".join(value.replace("\t", " ").replace("\n", " ") for value in values))
        return
    for item in changes:
        impact = f"；影响：{', '.join(item.consumers)}" if item.consumers else ""
        print(f"[{item.change_type}] {item.method.upper()} {item.path} ({item.operation_id}) {item.description}{impact}")


def render_service_map(root: Path) -> str:
    defaults, config = config_defaults(root)
    contracts = root / "contracts"
    services_config = config.get("services", []) if isinstance(config, dict) else []
    service_meta = {str(item.get("name")): item for item in services_config if isinstance(item, dict) and item.get("name")}
    registry_files = sorted((contracts / "_registry").glob("*.yaml"))
    consumer_files = sorted((contracts / "_consumers").glob("*.yaml"))
    provider_rows: list[str] = []
    dependencies: set[str] = set()
    for registry_file in registry_files:
        registry = load_yaml(registry_file)
        service = str(registry.get("service") or registry_file.stem)
        meta = service_meta.get(service, {})
        database = str(registry.get("database") or meta.get("database") or "-")
        status = str(meta.get("status") or "unknown")
        api_rel = str((registry.get("contract_files") or {}).get("api") or f"{service}/api.yaml")
        api_file = contracts / api_rel
        feign_ids: list[str] = []
        http_ids: list[str] = []
        if api_file.exists():
            document = load_yaml(api_file)
            feign_ids = [operation.operation_id for operation in iter_operations(document, service, api_file) if "Feign" in operation.tags and operation.operation_id]
            internal_http_tag = str(defaults.get("internal_http_tag", DEFAULT_INTERNAL_HTTP_TAG))
            http_ids = [operation.operation_id for operation in iter_operations(document, service, api_file) if internal_http_tag in operation.tags and operation.operation_id]
        events = (registry.get("contract_files") or {}).get("events") or []
        provider_rows.append(f"| {service} | {database} | `contracts/{api_rel}` | {status} | {'Yes (' + ', '.join(feign_ids) + ')' if feign_ids else 'No'} | {'Yes (' + ', '.join(http_ids) + ')' if http_ids else 'No'} | {'Yes' if events else 'No'} |")
        consumes = registry.get("consumes") or {}
        for entry in consumes.get("feign", []) or []:
            if isinstance(entry, dict):
                provider = entry.get("service") or entry.get("provider")
                if provider:
                    dependencies.add(f"{service} → {provider} (Feign: {entry.get('operationId', 'TBD')})")
        for entry in consumes.get("http", []) or []:
            if isinstance(entry, dict):
                provider = entry.get("service") or entry.get("provider")
                if provider:
                    dependencies.add(f"{service} → {provider} (HTTP: {entry.get('operationId', 'TBD')})")
        for entry in consumes.get("mq", []) or []:
            if isinstance(entry, dict):
                publisher = entry.get("publisher") or entry.get("service")
                if publisher:
                    dependencies.add(f"{service} → {publisher} (MQ: {entry.get('topic', 'TBD')})")
    consumer_rows: list[str] = []
    for consumer_file in consumer_files:
        consumer = load_yaml(consumer_file)
        consumer_rows.append(f"| {consumer.get('consumer', consumer_file.stem)} | {consumer.get('type', 'frontend')} | {consumer.get('framework', '-')} | `contracts/_consumers/{consumer_file.name}` |")
    tags = [str(value) for value in defaults.get("allowed_tags", DEFAULT_ALLOWED_TAGS)]
    internal = str(defaults.get("internal_path_prefix", "/internal/"))
    internal_http_tag = str(defaults.get("internal_http_tag", DEFAULT_INTERNAL_HTTP_TAG))
    tag_rows = []
    for tag in tags:
        caller = "前端 Consumer" if tag == "前端API" else "其他后端服务" if tag in {"Feign", internal_http_tag} else "外部系统"
        constraint = f"必须包含 `{internal}`" if tag in {"Feign", internal_http_tag} else "按接口安全设计"
        tag_rows.append(f"| `{tag}` | {caller} | {constraint} |")
    today = dt.date.today().isoformat()
    project_name = str(defaults.get("project_name") or "Project")
    return "\n".join([
        f"# Service Map: {project_name}",
        "",
        f"**Generated**: {today}",
        "**Config**: `.specify/extensions/contract-governance/contract-governance-config.yml`",
        "",
        "## Provider Services",
        "",
        "| Service | Database | Contract | Status | Feign Provider | HTTP Provider | MQ Provider |",
        "|---------|----------|----------|--------|---------------|---------------|-------------|",
        *provider_rows,
        "",
        "## Consumers",
        "",
        "| Consumer | Type | Framework | Contract |",
        "|----------|------|-----------|----------|",
        *consumer_rows,
        "",
        "## Service Dependencies",
        "",
        "```text",
        *(sorted(dependencies) or ["暂无已登记的跨服务依赖"]),
        "```",
        "",
        "## Tag Classification",
        "",
        "| Tag | 调用方 | 路径约束 |",
        "|-----|--------|----------|",
        *tag_rows,
        "",
    ])


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Contract governance semantic analyzer")
    subparsers = parser.add_subparsers(dest="command", required=True)

    validate = subparsers.add_parser("validate", help="Validate semantic contract rules")
    validate.add_argument("--repo-root", type=Path, required=True)
    validate.add_argument("--service", default="")
    validate.add_argument("--consumer", default="")
    validate.add_argument("--format", choices=("text", "json", "sarif"), default="text")
    validate.add_argument("--strict-warnings", action="store_true")

    diff = subparsers.add_parser("diff", help="Compare OpenAPI contracts semantically")
    diff.add_argument("--repo-root", type=Path, required=True)
    diff.add_argument("--service", required=True)
    diff.add_argument("--base", default="")
    diff.add_argument("--old-file", type=Path)
    diff.add_argument("--new-file", type=Path)
    diff.add_argument("--format", choices=("text", "json", "sarif", "tsv"), default="text")

    runtime = subparsers.add_parser("runtime-diff", help="Compare designed and exported runtime OpenAPI")
    runtime.add_argument("--contract", type=Path, required=True)
    runtime.add_argument("--runtime", type=Path, required=True)
    runtime.add_argument("--service", required=True)
    runtime.add_argument("--format", choices=("text", "json", "sarif", "tsv"), default="text")

    event = subparsers.add_parser("event-diff", help="Compare event schema compatibility")
    event.add_argument("--old", type=Path, required=True)
    event.add_argument("--new", type=Path, required=True)
    event.add_argument("--format", choices=("text", "json", "sarif"), default="text")

    service_map = subparsers.add_parser("service-map", help="Render or write SERVICE-MAP.md")
    service_map.add_argument("--repo-root", type=Path, required=True)
    service_map.add_argument("--write", action="store_true")
    return parser


def main() -> int:
    args = build_parser().parse_args()
    if args.command == "validate":
        findings = validate_semantics(args.repo_root.resolve(), args.service, args.consumer)
        emit_findings(findings, args.format)
        if any(item.severity == "error" for item in findings):
            return 1
        if args.strict_warnings and any(item.severity == "warning" for item in findings):
            return 2
        return 0
    if args.command == "diff":
        root = args.repo_root.resolve()
        new_file = args.new_file or root / "contracts" / args.service / "api.yaml"
        new_document = load_yaml(new_file)
        old_document = load_yaml(args.old_file) if args.old_file else git_old_document(root, args.service, args.base)
        if old_document is None:
            print(f"[contract-semantic] {args.service} 在比较基线中不存在，按新契约处理")
            return 0
        changes = semantic_diff(old_document, new_document, args.service, root)
        emit_changes(changes, args.format)
        return 2 if any(item.change_type == "breaking" for item in changes) else 0
    if args.command == "runtime-diff":
        old_document = load_yaml(args.contract)
        new_document = load_yaml(args.runtime)
        changes = semantic_diff(old_document, new_document, args.service)
        emit_changes(changes, args.format)
        return 2 if any(item.change_type == "breaking" for item in changes) else 0
    if args.command == "event-diff":
        old_document = load_yaml(args.old)
        new_document = load_yaml(args.new)
        old_schema = old_document.get("schema") or old_document.get("payload") or old_document.get("message") or old_document
        new_schema = new_document.get("schema") or new_document.get("payload") or new_document.get("message") or new_document
        changes = [Change(kind, code, "event", str(args.new), "", message) for kind, code, message in compare_schema(old_document, old_schema, new_document, new_schema)]
        emit_changes(changes, args.format)
        return 2 if any(item.change_type == "breaking" for item in changes) else 0
    if args.command == "service-map":
        content = render_service_map(args.repo_root.resolve())
        target = args.repo_root.resolve() / "contracts/SERVICE-MAP.md"
        if args.write:
            target.write_text(content, encoding="utf-8")
            print(f"[contract-governance] 已同步 {target}")
        else:
            print(content, end="")
        return 0
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
