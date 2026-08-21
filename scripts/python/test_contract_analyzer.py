#!/usr/bin/env python3

from __future__ import annotations

import contextlib
import importlib.util
import io
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

import yaml


MODULE_PATH = Path(__file__).with_name("contract_analyzer.py")
SPEC = importlib.util.spec_from_file_location("contract_analyzer", MODULE_PATH)
assert SPEC and SPEC.loader
analyzer = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = analyzer
SPEC.loader.exec_module(analyzer)


def write_yaml(path: Path, data: object) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(yaml.safe_dump(data, allow_unicode=True, sort_keys=False), encoding="utf-8")


def base_api(required_fields: list[str] | None = None) -> dict:
    required_fields = required_fields or []
    return {
        "openapi": "3.0.3",
        "info": {"title": "svc", "version": "1.0.0"},
        "paths": {
            "/api/v1/items": {
                "get": {
                    "tags": ["前端API"],
                    "operationId": "listItems",
                    "parameters": [
                        {"in": "query", "name": "page", "required": False, "schema": {"type": "integer"}}
                    ],
                    "responses": {
                        "200": {
                            "description": "ok",
                            "content": {"application/json": {"schema": {"$ref": "#/components/schemas/ItemPage"}}},
                        }
                    },
                }
            },
            "/internal/items": {
                "get": {
                    "tags": ["Feign"],
                    "operationId": "internalListItems",
                    "responses": {"200": {"description": "ok"}},
                }
            },
            "/internal/http-items": {
                "get": {
                    "tags": ["内部API"],
                    "operationId": "internalHttpListItems",
                    "responses": {"200": {"description": "ok"}},
                }
            },
        },
        "components": {
            "schemas": {
                "ItemPage": {
                    "type": "object",
                    "required": required_fields,
                    "properties": {
                        "total": {"type": "integer", "format": "int64"},
                        "records": {"type": "array", "items": {"$ref": "#/components/schemas/Item"}},
                    },
                },
                "Item": {
                    "type": "object",
                    "properties": {
                        "id": {"type": "integer", "format": "int64"},
                        "name": {"type": "string"},
                    },
                },
            }
        },
    }


class AnalyzerTest(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        write_yaml(
            self.root / ".specify/extensions/contract-governance/contract-governance-config.yml",
            {
                "defaults": {
                    "allowed_tags": ["前端API", "Feign", "内部API", "外部API"],
                    "internal_http_tag": "内部API",
                    "internal_path_prefix": "/internal/",
                    "internal_service_auth_mode": "network-only",
                    "consumer_statuses": ["PENDING", "RESOLVED", "MISMATCH"],
                    "change_ack_values": ["PENDING_ACK", "ACKNOWLEDGED"],
                    "pending_max_age_days": 30,
                },
                "services": [{"name": "svc", "database": "db_svc", "status": "active"}],
            },
        )
        write_yaml(
            self.root / "contracts/_registry/svc.yaml",
            {
                "service": "svc",
                "database": "db_svc",
                "contract_files": {"api": "svc/api.yaml", "events": []},
                "consumes": {"feign": [], "http": [], "mq": []},
            },
        )
        write_yaml(self.root / "contracts/svc/api.yaml", base_api())
        write_yaml(
            self.root / "contracts/_consumers/web.yaml",
            {
                "consumer": "web",
                "type": "frontend",
                "generated": "2026-01-01",
                "consumes": {
                    "http": [
                        {
                            "provider": "svc",
                            "operationId": "listItems",
                            "status": "RESOLVED",
                            "required_fields": ["total", "records"],
                        }
                    ]
                },
            },
        )
        (self.root / "contracts/SERVICE-MAP.md").write_text(
            "| svc | db_svc | `contracts/svc/api.yaml` | active |\n"
            "| web | frontend | Vue | `contracts/_consumers/web.yaml` |\n",
            encoding="utf-8",
        )

    def tearDown(self) -> None:
        self.temp.cleanup()

    def git_baseline(self) -> str:
        subprocess.run(["git", "init", "-q", str(self.root)], check=True)
        subprocess.run(["git", "-C", str(self.root), "config", "user.email", "test@example.com"], check=True)
        subprocess.run(["git", "-C", str(self.root), "config", "user.name", "Contract Test"], check=True)
        subprocess.run(["git", "-C", str(self.root), "add", "."], check=True)
        subprocess.run(["git", "-C", str(self.root), "commit", "-qm", "baseline"], check=True)
        return subprocess.run(
            ["git", "-C", str(self.root), "rev-parse", "HEAD"], check=True, capture_output=True, text=True
        ).stdout.strip()

    def test_valid_required_fields_pass(self) -> None:
        findings = analyzer.validate_semantics(self.root)
        self.assertFalse([item for item in findings if item.severity == "error"])

    def test_resolved_missing_required_field_fails(self) -> None:
        consumer = analyzer.load_yaml(self.root / "contracts/_consumers/web.yaml")
        consumer["consumes"]["http"][0]["required_fields"].append("missing")
        write_yaml(self.root / "contracts/_consumers/web.yaml", consumer)
        findings = analyzer.validate_semantics(self.root)
        self.assertIn("resolved-required-fields-missing", {item.code for item in findings})

    def test_pending_age_is_reported(self) -> None:
        consumer = analyzer.load_yaml(self.root / "contracts/_consumers/web.yaml")
        consumer["consumes"]["http"][0]["status"] = "PENDING"
        consumer["consumes"]["http"][0]["since"] = "2020-01-01"
        write_yaml(self.root / "contracts/_consumers/web.yaml", consumer)
        findings = analyzer.validate_semantics(self.root)
        self.assertIn("pending-stale", {item.code for item in findings})

    def test_pending_age_threshold_can_be_disabled(self) -> None:
        config_file = self.root / ".specify/extensions/contract-governance/contract-governance-config.yml"
        config = analyzer.load_yaml(config_file)
        config["defaults"]["pending_max_age_days"] = 0
        write_yaml(config_file, config)
        consumer = analyzer.load_yaml(self.root / "contracts/_consumers/web.yaml")
        consumer["consumes"]["http"][0]["status"] = "PENDING"
        consumer["consumes"]["http"][0]["since"] = "2020-01-01"
        write_yaml(self.root / "contracts/_consumers/web.yaml", consumer)
        findings = analyzer.validate_semantics(self.root)
        self.assertNotIn("pending-stale", {item.code for item in findings})

    def test_service_map_drift_is_reported(self) -> None:
        (self.root / "contracts/SERVICE-MAP.md").write_text("# empty\n", encoding="utf-8")
        findings = analyzer.validate_semantics(self.root)
        codes = {item.code for item in findings}
        self.assertIn("service-map-provider-missing", codes)
        self.assertIn("service-map-consumer-missing", codes)

    def test_registry_rejects_derived_provider_summaries(self) -> None:
        registry_file = self.root / "contracts/_registry/svc.yaml"
        registry = analyzer.load_yaml(registry_file)
        registry["feign_operations"] = [{"operationId": "internalListItems", "callers": ["web"]}]
        registry["http_operations"] = [{"operationId": "internalHttpListItems", "callers": ["svc"]}]
        registry["mq_operations"] = []
        write_yaml(registry_file, registry)
        findings = analyzer.validate_semantics(self.root)
        forbidden = [item for item in findings if item.code == "registry-derived-summary-forbidden"]
        self.assertEqual(3, len(forbidden))

    def test_internal_http_path_must_use_internal_prefix(self) -> None:
        api_file = self.root / "contracts/svc/api.yaml"
        api = analyzer.load_yaml(api_file)
        operation = api["paths"].pop("/internal/http-items")
        api["paths"]["/api/v1/http-items"] = operation
        write_yaml(api_file, api)
        findings = analyzer.validate_semantics(self.root)
        self.assertIn("internal-http-path-invalid", {item.code for item in findings})

    def test_network_only_rejects_internal_operation_security(self) -> None:
        api_file = self.root / "contracts/svc/api.yaml"
        api = analyzer.load_yaml(api_file)
        api["paths"]["/internal/items"]["get"]["security"] = [{"serviceAuth": []}]
        write_yaml(api_file, api)
        findings = analyzer.validate_semantics(self.root)
        forbidden = [item for item in findings if item.code == "internal-service-auth-forbidden"]
        self.assertEqual(1, len(forbidden))
        self.assertEqual("internalListItems", forbidden[0].message.split(" 是", maxsplit=1)[0].split(".")[-1])

    def test_network_only_rejects_inherited_security_and_allows_explicit_empty_override(self) -> None:
        api_file = self.root / "contracts/svc/api.yaml"
        api = analyzer.load_yaml(api_file)
        api["security"] = [{"bearerAuth": []}]
        api["paths"]["/internal/items"]["get"]["security"] = []
        write_yaml(api_file, api)
        findings = analyzer.validate_semantics(self.root)
        forbidden_pointers = {
            item.pointer for item in findings if item.code == "internal-service-auth-forbidden"
        }
        self.assertNotIn("GET /internal/items", forbidden_pointers)
        self.assertIn("GET /internal/http-items", forbidden_pointers)
        self.assertNotIn("GET /api/v1/items", forbidden_pointers)

    def test_provider_defined_allows_internal_operation_security(self) -> None:
        config_file = self.root / ".specify/extensions/contract-governance/contract-governance-config.yml"
        config = analyzer.load_yaml(config_file)
        config["defaults"]["internal_service_auth_mode"] = "provider-defined"
        write_yaml(config_file, config)
        api_file = self.root / "contracts/svc/api.yaml"
        api = analyzer.load_yaml(api_file)
        api["paths"]["/internal/items"]["get"]["security"] = [{"serviceAuth": []}]
        write_yaml(api_file, api)
        findings = analyzer.validate_semantics(self.root)
        self.assertNotIn("internal-service-auth-forbidden", {item.code for item in findings})

    def test_invalid_internal_service_auth_mode_fails(self) -> None:
        config_file = self.root / ".specify/extensions/contract-governance/contract-governance-config.yml"
        config = analyzer.load_yaml(config_file)
        config["defaults"]["internal_service_auth_mode"] = "unknown"
        write_yaml(config_file, config)
        findings = analyzer.validate_semantics(self.root)
        self.assertIn("internal-service-auth-mode-invalid", {item.code for item in findings})

    def test_resolved_internal_http_dependency_must_exist(self) -> None:
        registry_file = self.root / "contracts/_registry/svc.yaml"
        registry = analyzer.load_yaml(registry_file)
        registry["consumes"]["http"] = [
            {"service": "missing", "operationId": "startMissing", "status": "RESOLVED"}
        ]
        write_yaml(registry_file, registry)
        findings = analyzer.validate_semantics(self.root)
        self.assertIn("resolved-http-operation-missing", {item.code for item in findings})

    def test_internal_http_dependency_requires_internal_tag(self) -> None:
        registry_file = self.root / "contracts/_registry/svc.yaml"
        registry = analyzer.load_yaml(registry_file)
        registry["consumes"]["http"] = [
            {"service": "svc", "operationId": "listItems", "status": "PENDING"}
        ]
        write_yaml(registry_file, registry)
        findings = analyzer.validate_semantics(self.root)
        self.assertIn("backend-consumes-non-internal-http", {item.code for item in findings})

    def test_frontend_cannot_consume_internal_http_operation(self) -> None:
        consumer_file = self.root / "contracts/_consumers/web.yaml"
        consumer = analyzer.load_yaml(consumer_file)
        consumer["consumes"]["http"][0]["operationId"] = "internalHttpListItems"
        write_yaml(consumer_file, consumer)
        findings = analyzer.validate_semantics(self.root)
        self.assertIn("frontend-consumes-internal-http", {item.code for item in findings})

    def test_semantic_diff_detects_response_field_removal(self) -> None:
        old = base_api()
        new = base_api()
        del new["components"]["schemas"]["ItemPage"]["properties"]["total"]
        changes = analyzer.semantic_diff(old, new, "svc", self.root)
        breaking_codes = {item.code for item in changes if item.change_type == "breaking"}
        self.assertIn("response-field-removed", breaking_codes)
        impacted = {consumer for item in changes for consumer in item.consumers}
        self.assertIn("frontend:web", impacted)

    def test_semantic_diff_detects_parameter_and_tag_changes(self) -> None:
        old = base_api()
        new = base_api()
        operation = new["paths"]["/api/v1/items"]["get"]
        operation["tags"] = ["Feign"]
        operation["parameters"][0]["required"] = True
        changes = analyzer.semantic_diff(old, new, "svc")
        codes = {item.code for item in changes}
        self.assertIn("operation-tags-changed", codes)
        self.assertIn("request-parameter-required", codes)

    def test_fingerprint_is_stable_and_sensitive_to_description(self) -> None:
        change = analyzer.Change("breaking", "operation-removed", "GET", "/items", "listItems", "removed")
        first = change.fingerprint("svc")
        second = analyzer.Change("breaking", "operation-removed", "get", "/items", "listItems", "removed").fingerprint("svc")
        different = analyzer.Change("breaking", "operation-removed", "get", "/items", "listItems", "changed").fingerprint("svc")
        self.assertEqual(first, second)
        self.assertRegex(first, r"^sha256:[0-9a-f]{64}$")
        self.assertNotEqual(first, different)

    def test_group_changes_aggregates_operation_and_prefers_breaking(self) -> None:
        changes = [
            analyzer.Change("non-breaking", "response-status-added", "get", "/items", "listItems", "状态码新增：202"),
            analyzer.Change("breaking", "response-field-removed", "get", "/items", "listItems", "字段删除：a:b\n下一行"),
        ]
        entries = analyzer.group_changes("svc", changes, base_api(), analyzer.dt.date(2026, 8, 21))
        self.assertEqual(1, len(entries))
        self.assertEqual("breaking", entries[0]["type"])
        self.assertEqual("1.0.0", entries[0]["version"])
        self.assertRegex(entries[0]["id"], r"^2026-08-21-[0-9a-f]{12}$")
        self.assertEqual(2, len(entries[0]["changes"]))
        invalid = {"openapi": "3.0.3", "info": {"version": "1.0.0"}, "paths": {}, "x-changelog": entries}
        invalid["x-changelog"][0]["type"] = "non-breaking"
        findings = analyzer.validate_changelog(invalid, "svc", "contracts/svc/api.yaml")
        self.assertIn("changelog-aggregate-type-invalid", {item.code for item in findings})

    def test_changelog_write_is_valid_and_idempotent(self) -> None:
        api_file = self.root / "contracts/svc/api.yaml"
        change = analyzer.Change("non-breaking", "demo", "get", "/api/v1/items", "listItems", "包含冒号: 引号 ' 和\n多行")
        entries = analyzer.group_changes("svc", [change], base_api(), analyzer.dt.date(2026, 8, 21))
        self.assertEqual(1, analyzer.write_changelog(api_file, entries))
        self.assertEqual(0, analyzer.write_changelog(api_file, entries))
        parsed = analyzer.load_yaml(api_file)
        self.assertEqual(change.fingerprint("svc"), parsed["x-changelog"][0]["changes"][0]["fingerprint"])

    def test_check_changelog_requires_complete_coverage(self) -> None:
        baseline = self.git_baseline()
        api_file = self.root / "contracts/svc/api.yaml"
        api = analyzer.load_yaml(api_file)
        api["paths"]["/api/v1/items"]["get"]["parameters"][0]["required"] = True
        api["paths"]["/api/v1/items"]["get"]["responses"]["202"] = {"description": "accepted"}
        write_yaml(api_file, api)
        rc, findings, _ = analyzer.check_changelog(self.root, baseline, ["svc"], True)
        self.assertEqual(2, rc)
        self.assertEqual(2, len([item for item in findings if item.code == "changelog-coverage-missing"]))
        auto_rc, auto_findings, _ = analyzer.check_changelog(self.root, baseline, [], True)
        self.assertEqual(2, auto_rc)
        self.assertEqual(2, len([item for item in auto_findings if item.code == "changelog-coverage-missing"]))
        changes = analyzer.semantic_diff(analyzer.git_old_document(self.root, "svc", baseline), api, "svc", self.root)
        entries = analyzer.group_changes("svc", changes, api, analyzer.dt.date(2026, 8, 21))
        analyzer.write_changelog(api_file, entries)
        rc, findings, _ = analyzer.check_changelog(self.root, baseline, ["svc"], True)
        self.assertEqual(0, rc)
        self.assertIn("changelog-coverage-complete", {item.code for item in findings})

    def test_check_changelog_rejects_partial_wrong_and_duplicate_coverage(self) -> None:
        baseline = self.git_baseline()
        api_file = self.root / "contracts/svc/api.yaml"
        api = analyzer.load_yaml(api_file)
        operation = api["paths"]["/api/v1/items"]["get"]
        operation["parameters"][0]["required"] = True
        operation["responses"]["202"] = {"description": "accepted"}
        old = analyzer.git_old_document(self.root, "svc", baseline)
        entries = analyzer.group_changes("svc", analyzer.semantic_diff(old, api, "svc"), api)
        entries[0]["changes"] = entries[0]["changes"][:1]
        entries[0]["method"] = "post"
        api["x-changelog"] = entries
        write_yaml(api_file, api)
        rc, findings, _ = analyzer.check_changelog(self.root, baseline, ["svc"], True)
        self.assertEqual(2, rc)
        codes = {item.code for item in findings}
        self.assertIn("changelog-coverage-missing", codes)
        self.assertIn("changelog-operation-group-invalid", codes)
        api = analyzer.load_yaml(api_file)
        duplicate = dict(api["x-changelog"][0])
        duplicate["id"] = "duplicate"
        api["x-changelog"].append(duplicate)
        write_yaml(api_file, api)
        _, findings, _ = analyzer.check_changelog(self.root, baseline, ["svc"], True)
        self.assertIn("changelog-fingerprint-duplicate", {item.code for item in findings})

    def test_description_only_change_and_new_provider_are_exempt(self) -> None:
        baseline = self.git_baseline()
        api_file = self.root / "contracts/svc/api.yaml"
        api = analyzer.load_yaml(api_file)
        api["info"]["description"] = "documentation only"
        write_yaml(api_file, api)
        rc, findings, _ = analyzer.check_changelog(self.root, baseline, ["svc"], True)
        self.assertEqual(0, rc, [item.as_dict() for item in findings])
        write_yaml(self.root / "contracts/new-svc/api.yaml", base_api())
        rc, findings, _ = analyzer.check_changelog(self.root, baseline, ["new-svc"], True)
        self.assertEqual(0, rc)
        self.assertIn("provider-contract-initial", {item.code for item in findings})

    def test_legacy_changelog_does_not_cover_new_change(self) -> None:
        baseline = self.git_baseline()
        api_file = self.root / "contracts/svc/api.yaml"
        api = analyzer.load_yaml(api_file)
        api["paths"]["/api/v1/items"]["get"]["parameters"][0]["required"] = True
        api["x-changelog"] = [{"id": "legacy-1", "date": "2026-08-21", "type": "breaking", "summary": "legacy"}]
        write_yaml(api_file, api)
        rc, findings, _ = analyzer.check_changelog(self.root, baseline, ["svc"], True)
        self.assertEqual(2, rc)
        self.assertIn("changelog-coverage-missing", {item.code for item in findings})

    def test_json_and_sarif_reports(self) -> None:
        findings = [analyzer.Finding("warning", "demo", "message", "contracts/demo.yaml")]
        stream = io.StringIO()
        with contextlib.redirect_stdout(stream):
            analyzer.emit_findings(findings, "json")
        self.assertEqual(1, yaml.safe_load(stream.getvalue())["summary"]["warnings"])
        stream = io.StringIO()
        with contextlib.redirect_stdout(stream):
            analyzer.emit_findings(findings, "sarif")
        self.assertEqual("2.1.0", yaml.safe_load(stream.getvalue())["version"])

    def test_change_sarif_report(self) -> None:
        changes = [
            analyzer.Change(
                "breaking", "operation-removed", "get", "/items", "listItems", "operation 已删除", ["frontend:web"]
            )
        ]
        stream = io.StringIO()
        with contextlib.redirect_stdout(stream):
            analyzer.emit_changes(changes, "sarif")
        payload = yaml.safe_load(stream.getvalue())
        self.assertEqual("2.1.0", payload["version"])
        self.assertEqual("operation-removed", payload["runs"][0]["results"][0]["ruleId"])

    def test_service_map_render_contains_registered_entities(self) -> None:
        rendered = analyzer.render_service_map(self.root)
        self.assertIn("contracts/svc/api.yaml", rendered)
        self.assertIn("contracts/_consumers/web.yaml", rendered)
        self.assertIn("internalListItems", rendered)
        self.assertIn("internalHttpListItems", rendered)
        self.assertIn("HTTP Provider", rendered)

    def test_http_dependency_is_in_impact_and_service_map(self) -> None:
        registry_file = self.root / "contracts/_registry/svc.yaml"
        registry = analyzer.load_yaml(registry_file)
        registry["consumes"]["http"] = [
            {"service": "svc", "operationId": "internalHttpListItems", "status": "PENDING"}
        ]
        write_yaml(registry_file, registry)
        rendered = analyzer.render_service_map(self.root)
        self.assertIn("svc → svc (HTTP: internalHttpListItems)", rendered)
        self.assertIn("backend:svc", analyzer.consumer_impact(self.root, "svc", "internalHttpListItems"))

    def test_event_schema_breaking_change(self) -> None:
        old = {"type": "object", "properties": {"id": {"type": "integer"}}}
        new = {"type": "object", "properties": {}}
        changes = analyzer.compare_schema(old, old, new, new)
        self.assertIn("response-field-removed", {code for _, code, _ in changes})


if __name__ == "__main__":
    unittest.main()
