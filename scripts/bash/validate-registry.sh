#!/usr/bin/env bash

set -eo pipefail

SERVICE_FILTER=""
CONSUMER_FILTER=""
FEATURE_DIR_ARG=""
BOOTSTRAP_OK=false
STRICT=true

usage() {
    cat << 'EOF'
Usage: validate-registry.sh [--service <service-name>] [--consumer <consumer-name>] [--feature-dir <path>] [--bootstrap-ok]

校验根目录 contracts/ 微服务契约注册表和前端消费契约。

Options:
  --service <name>      只校验指定服务
  --consumer <name>     只校验指定前端消费方
  --feature-dir <path>  使用指定 feature 的 plan.md 判断微服务范围
  --bootstrap-ok        contracts/ 不存在时允许跳过，并提示初始化命令
  --help, -h            显示帮助信息
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --service)
            [[ $# -ge 2 ]] || { echo "ERROR: --service 需要服务名" >&2; exit 1; }
            SERVICE_FILTER="$2"
            shift 2
            ;;
        --consumer)
            [[ $# -ge 2 ]] || { echo "ERROR: --consumer 需要消费方名称" >&2; exit 1; }
            CONSUMER_FILTER="$2"
            shift 2
            ;;
        --feature-dir)
            [[ $# -ge 2 ]] || { echo "ERROR: --feature-dir 需要路径" >&2; exit 1; }
            FEATURE_DIR_ARG="$2"
            shift 2
            ;;
        --bootstrap-ok)
            BOOTSTRAP_OK=true
            STRICT=false
            shift
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        *)
            echo "ERROR: 未知参数 '$1'" >&2
            usage >&2
            exit 1
            ;;
    esac
done

SCRIPT_DIR="$(CDPATH="" cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load common utilities (repo root detection, feature dir resolution, string helpers)
# shellcheck source=common-utils.sh
source "$SCRIPT_DIR/common-utils.sh"

# Try to load project-level common.sh if available (provides get_repo_root override)
COMMON_SH="$SCRIPT_DIR/../../../../scripts/bash/common.sh"
if [[ -f "$COMMON_SH" ]]; then
    # shellcheck source=/dev/null
    source "$COMMON_SH"
fi

# Load configurable values from contract-governance-config.yml
# shellcheck source=common-config.sh
source "$SCRIPT_DIR/common-config.sh"
# Build grep-friendly patterns from CSV config
ALLOWED_TAGS_PATTERN="${CG_ALLOWED_TAGS_CSV//,/|}"
ALLOWED_STATUSES_PATTERN="${CG_CONSUMER_STATUSES_CSV//,/|}"

is_valid_consumer_status() {
    printf '%s\n' "${CG_CONSUMER_STATUSES_CSV//,/$'\n'}" | grep -Eqx "$1"
}

REPO_ROOT="$(get_repo_root "$SCRIPT_DIR")"
CONTRACTS_DIR="$REPO_ROOT/contracts"
REGISTRY_DIR="$CONTRACTS_DIR/_registry"
CONSUMERS_DIR="$CONTRACTS_DIR/_consumers"

failures=()
warnings=()
registry_files=()
consumer_files=()

add_failure() {
    failures+=("$1")
}

add_warning() {
    warnings+=("$1")
}

FEATURE_DIR="$(resolve_feature_dir "$FEATURE_DIR_ARG" "$REPO_ROOT" || true)"
PLAN_FILE=""
if [[ -n "$FEATURE_DIR" && -f "$FEATURE_DIR/plan.md" ]]; then
    PLAN_FILE="$FEATURE_DIR/plan.md"
fi

plan_mentions_microservice_contract() {
    [[ -n "$PLAN_FILE" ]] || return 1
    grep -Eiq "微服务|服务边界|Feign|RocketMQ|MQ|contracts/|api\\.yaml|_consumers|消费契约|Provider|Consumer|PENDING|RESOLVED|MISMATCH|跨服务|直连数据库" "$PLAN_FILE"
}

plan_allows_shared_frontend_feign() {
    [[ -n "$PLAN_FILE" ]] || return 1
    grep -Eiq "共用接口例外|前端API.*Feign.*例外|Feign.*前端API.*例外|同时.*前端.*Feign.*(理由|例外)|同时.*Feign.*前端.*(理由|例外)" "$PLAN_FILE"
}

if [[ ! -d "$CONTRACTS_DIR" ]]; then
    if [[ -n "$SERVICE_FILTER" && "$STRICT" == "true" ]]; then
        add_failure "指定了 --service ${SERVICE_FILTER}，但仓库缺少 contracts/；请先运行 .specify/extensions/contract-governance/scripts/bash/init-registry.sh --service ${SERVICE_FILTER}"
    elif [[ -n "$CONSUMER_FILTER" && "$STRICT" == "true" ]]; then
        add_failure "指定了 --consumer ${CONSUMER_FILTER}，但仓库缺少 contracts/；请先运行 .specify/extensions/contract-governance/scripts/bash/init-consumer.sh --consumer ${CONSUMER_FILTER}"
    elif plan_mentions_microservice_contract && [[ "$STRICT" == "true" ]]; then
        add_failure "当前 feature 涉及微服务或契约，但仓库缺少 contracts/；请先运行 .specify/extensions/contract-governance/scripts/bash/init-registry.sh --service <service-name>，前端消费方再运行 init-consumer.sh --consumer <consumer-name>"
    else
        echo "[contract-governance] 未发现 contracts/，当前模式允许 bootstrap，已跳过注册表校验"
        exit 0
    fi
fi

if [[ -d "$CONTRACTS_DIR" ]]; then
    [[ -f "$CONTRACTS_DIR/SERVICE-MAP.md" ]] || add_failure "缺少 contracts/SERVICE-MAP.md"
    [[ -d "$REGISTRY_DIR" ]] || add_failure "缺少 contracts/_registry/"
fi

if [[ ${#failures[@]} -eq 0 && -d "$REGISTRY_DIR" ]]; then
    shopt -s nullglob
    registry_files=()
    if [[ -n "$SERVICE_FILTER" ]]; then
        registry_files=("$REGISTRY_DIR/$SERVICE_FILTER.yaml")
        [[ -f "${registry_files[0]}" ]] || add_failure "未找到服务 registry：contracts/_registry/$SERVICE_FILTER.yaml"
    else
        registry_files=("$REGISTRY_DIR"/*.yaml)
        [[ ${#registry_files[@]} -gt 0 ]] || add_failure "contracts/_registry/ 中没有服务 registry 文件"
    fi
    shopt -u nullglob
fi

if [[ -d "$CONTRACTS_DIR" ]]; then
    shopt -s nullglob
    consumer_files=()
    if [[ -n "$CONSUMER_FILTER" ]]; then
        consumer_files=("$CONSUMERS_DIR/$CONSUMER_FILTER.yaml")
        [[ -f "${consumer_files[0]}" ]] || add_failure "未找到前端消费契约：contracts/_consumers/$CONSUMER_FILTER.yaml"
    elif [[ -d "$CONSUMERS_DIR" ]]; then
        consumer_files=("$CONSUMERS_DIR"/*.yaml)
    fi
    shopt -u nullglob
fi

extract_scalar() {
    local file="$1"
    local key="$2"
    local line
    line="$(grep -E "^[[:space:]]*$key:" "$file" | head -n 1 || true)"
    [[ -n "$line" ]] || { printf '%s' ''; return 0; }
    trim_value "${line#*:}"
}

extract_api_path() {
    local file="$1"
    awk '
      /^[[:space:]]*contract_files:/ { in_cf=1; next }
      in_cf && /^[^[:space:]]/ { in_cf=0 }
      in_cf && /^[[:space:]]+api:/ {
        sub(/^[[:space:]]+api:[[:space:]]*/, "", $0)
        sub(/[[:space:]]*#.*/, "", $0)
        print $0
        exit
      }
    ' "$file" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
}

extract_event_paths() {
    local file="$1"
    awk '
      /^[[:space:]]*events:/ { in_events=1; next }
      in_events && /^[[:space:]]*[A-Za-z0-9_.-]+:/ { in_events=0 }
      in_events && /^[[:space:]]*-/ {
        sub(/^[[:space:]]*-[[:space:]]*/, "", $0)
        sub(/[[:space:]]*#.*/, "", $0)
        if ($0 != "") print $0
      }
    ' "$file" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
}

extract_openapi_operations() {
    local api_file="$1"
    awk '
      function trim(s) {
        gsub(/^[[:space:]]+/, "", s)
        gsub(/[[:space:]]+$/, "", s)
        return s
      }
      function emit() {
        if (in_operation) {
          print current_path "\t" current_method "\t" operation_id "\t" tags
        }
      }
      /^[[:space:]]{2}\/[^:]+:/ {
        emit()
        current_path=$1
        sub(/:$/, "", current_path)
        in_operation=0
        in_tags=0
        next
      }
      /^[[:space:]]{4}(get|post|put|delete|patch|options|head):/ {
        emit()
        current_method=$1
        sub(/:$/, "", current_method)
        operation_id=""
        tags=""
        in_operation=1
        in_tags=0
        next
      }
      in_operation && /^[[:space:]]{6}operationId:/ {
        operation_id=$0
        sub(/^[[:space:]]*operationId:[[:space:]]*/, "", operation_id)
        operation_id=trim(operation_id)
        next
      }
      in_operation && /^[[:space:]]{6}tags:/ {
        tags=$0
        sub(/^[[:space:]]*tags:[[:space:]]*/, "", tags)
        tags=trim(tags)
        in_tags=(tags == "")
        next
      }
      in_operation && in_tags && /^[[:space:]]{8}-[[:space:]]*/ {
        tag=$0
        sub(/^[[:space:]]*-[[:space:]]*/, "", tag)
        tag=trim(tag)
        tags=(tags == "" ? tag : tags "," tag)
        next
      }
      END {
        emit()
      }
    ' "$api_file"
}

extract_xchangelog_entries() {
    local file="$1"
    awk '
      function trim(s) {
        gsub(/^[[:space:]]+/, "", s)
        gsub(/^[[:space:]]+$/, "", s)
        return s
      }
      function emit() {
        if (in_entry && id != "") {
          print id "\t" type_val "\t" date_val "\t" summary_val
        }
      }
      /^x-changelog:/ { in_cl=1; next }
      in_cl && /^[^[:space:]#]/ { emit(); in_cl=0; in_entry=0; next }
      in_cl && /^[[:space:]]*-[[:space:]]*id:/ {
        emit()
        id=$0
        sub(/^[[:space:]]*-[[:space:]]*id:[[:space:]]*/, "", id)
        gsub(/["'"'"']/, "", id)
        id=trim(id)
        type_val=""; date_val=""; summary_val=""
        in_entry=1
        next
      }
      in_cl && in_entry {
        if ($0 ~ /^[[:space:]]+type:/) {
          type_val=$0
          sub(/^[[:space:]]*type:[[:space:]]*/, "", type_val)
          type_val=trim(type_val)
          next
        }
        if ($0 ~ /^[[:space:]]+date:/) {
          date_val=$0
          sub(/^[[:space:]]*date:[[:space:]]*/, "", date_val)
          gsub(/["'"'"']/, "", date_val)
          date_val=trim(date_val)
          next
        }
        if ($0 ~ /^[[:space:]]+summary:/) {
          summary_val=$0
          sub(/^[[:space:]]*summary:[[:space:]]*/, "", summary_val)
          gsub(/["'"'"']/, "", summary_val)
          summary_val=trim(summary_val)
          next
        }
      }
      END { emit() }
    ' "$file"
}

extract_consumer_http_entries() {
    local file="$1"
    awk '
      function trim(s) {
        gsub(/^[[:space:]]+/, "", s)
        gsub(/[[:space:]]+$/, "", s)
        return s
      }
      function emit() {
        if (in_item) {
          print provider "\t" operation_id "\t" status
          in_item=0
          provider=""
          operation_id=""
          status=""
        }
      }
      /^[[:space:]]*consumes:/ { in_consumes=1; next }
      in_consumes && /^[^[:space:]]/ {
        emit()
        in_consumes=0
        in_http=0
        next
      }
      in_consumes && /^[[:space:]]*http:[[:space:]]*\[\][[:space:]]*$/ {
        in_http=0
        next
      }
      in_consumes && /^[[:space:]]*http:/ {
        in_http=1
        next
      }
      in_http && /^[[:space:]]{4}-[[:space:]]*provider:/ {
        emit()
        provider=$0
        sub(/^[[:space:]]*-[[:space:]]*provider:[[:space:]]*/, "", provider)
        provider=trim(provider)
        in_item=1
        next
      }
      in_http && in_item && /^[[:space:]]+operationId:/ {
        operation_id=$0
        sub(/^[[:space:]]*operationId:[[:space:]]*/, "", operation_id)
        operation_id=trim(operation_id)
        next
      }
      in_http && in_item && /^[[:space:]]+status:/ {
        status=$0
        sub(/^[[:space:]]*status:[[:space:]]*/, "", status)
        status=trim(status)
        next
      }
      END {
        emit()
      }
    ' "$file"
}

operation_tags_for_id() {
    local api_file="$1"
    local operation_id="$2"
    [[ -n "$operation_id" ]] || return 1
    extract_openapi_operations "$api_file" | awk -F '\t' -v operation_id="$operation_id" '
      $3 == operation_id {
        print $4
        found=1
        exit
      }
      END {
        if (!found) exit 1
      }
    '
}

validate_api_file() {
    local service="$1"
    local api_file="$2"
    [[ -f "$api_file" ]] || { add_failure "$service 的 api.yaml 不存在：${api_file#$REPO_ROOT/}"; return; }

    grep -Eq "^openapi:" "$api_file" || add_failure "$service/api.yaml 缺少 openapi 版本"
    grep -Eq "^paths:" "$api_file" || add_failure "$service/api.yaml 缺少 paths"
    grep -Eq "^components:" "$api_file" || add_failure "$service/api.yaml 缺少 components"

    # x-changelog 校验
    if grep -Eq "^x-changelog:" "$api_file"; then
        local xcl_breaking_count=0
        while IFS=$'\t' read -r xcl_id xcl_type xcl_date xcl_summary; do
            [[ -z "$xcl_id" ]] && continue
            if [[ -z "$xcl_type" ]]; then
                add_failure "$service/api.yaml x-changelog 条目 $xcl_id 缺少 type"
            elif ! printf '%s\n' "${CG_CHANGELOG_TYPES_CSV//,/$'\n'}" | grep -Eqx "$xcl_type"; then
                add_failure "$service/api.yaml x-changelog 条目 $xcl_id 使用了非法 type：$xcl_type（仅允许 ${CG_CHANGELOG_TYPES_CSV//,//}）"
            fi
            [[ -z "$xcl_date" ]] && add_failure "$service/api.yaml x-changelog 条目 $xcl_id 缺少 date"
            [[ -z "$xcl_summary" ]] && add_warning "$service/api.yaml x-changelog 条目 $xcl_id 缺少 summary"
            [[ "$xcl_type" == "breaking" ]] && xcl_breaking_count=$((xcl_breaking_count + 1))
        done < <(extract_xchangelog_entries "$api_file")
        if [[ $xcl_breaking_count -gt 0 ]]; then
            echo "[contract-governance] 提示：$service/api.yaml 的 x-changelog 中有 $xcl_breaking_count 个 breaking change，消费方需要关注" >&2
        fi
    fi

    if ! grep -Eq "^paths:[[:space:]]*\\{\\}" "$api_file"; then
        grep -Eq "operationId:" "$api_file" || add_failure "$service/api.yaml 存在非空 paths 但缺少 operationId"
        if ! grep -Eq "/api/v[0-9]+/" "$api_file" && ! grep -Fq "$CG_INTERNAL_PATH_PREFIX" "$api_file"; then
            add_failure "$service/api.yaml 存在非空 paths 但既没有 /api/vN/ 路径，也没有 ${CG_INTERNAL_PATH_PREFIX} 内部路径"
        fi
        # Check for response wrapper schema under components.schemas (only when configured)
        if [[ -n "${CG_RESPONSE_WRAPPER_SCHEMAS:-}" ]]; then
            local has_result_wrapper=false
            local wrapper_patterns="${CG_RESPONSE_WRAPPER_SCHEMAS//,/|}"
            if awk -v pat="^($wrapper_patterns)" '/^components:/ {in_c=1; next} in_c && /^  schemas:/ {in_s=1; next} in_c && in_s && /^    [A-Za-z]/ {key=$1; sub(/:$/, "", key); if (key ~ pat) {found=1; exit}} /^[^ ]/ {in_c=0; in_s=0} END {exit !found}' "$api_file" 2>/dev/null; then
                has_result_wrapper=true
            fi
            # Also accept $ref patterns pointing to wrapper-type schemas in responses
            if [[ "$has_result_wrapper" == "false" ]] && grep -Eq "\\\$ref:.*#/components/schemas/(${wrapper_patterns})" "$api_file" 2>/dev/null; then
                has_result_wrapper=true
            fi
            if [[ "$has_result_wrapper" == "false" ]]; then
                add_warning "$service/api.yaml 未明显声明响应包装结构（components.schemas 中未发现 ${CG_RESPONSE_WRAPPER_SCHEMAS//,/ /} 定义）"
            fi
        fi

        while IFS=$'\t' read -r path method operation_id tags; do
            [[ -z "$path" || -z "$method" ]] && continue
            local operation_label="$service/api.yaml $method $path"
            [[ -n "$operation_id" ]] && operation_label="$operation_label ($operation_id)"

            if [[ -z "$tags" ]]; then
                add_failure "$operation_label 缺少 tags，必须声明 ${CG_ALLOWED_TAGS_CSV//,/ /} 至少一种调用方标签"
                continue
            fi

            if ! printf '%s\n' "$tags" | grep -Eq "$ALLOWED_TAGS_PATTERN"; then
                add_failure "$operation_label 的 tags 必须包含 ${CG_ALLOWED_TAGS_CSV//,/ /} 至少一种调用方标签，当前为：$tags"
            fi

            if printf '%s\n' "$tags" | grep -Eq "Feign"; then
                if [[ "$path" != *"$CG_INTERNAL_PATH_PREFIX"* ]]; then
                    add_failure "$operation_label 标记为 Feign，但路径未包含 ${CG_INTERNAL_PATH_PREFIX}；Feign 接口默认不得暴露给前端"
                fi
            fi

            if printf '%s\n' "$tags" | grep -Fq "$CG_INTERNAL_HTTP_TAG"; then
                if [[ "$path" != *"$CG_INTERNAL_PATH_PREFIX"* ]]; then
                    add_failure "$operation_label 标记为 ${CG_INTERNAL_HTTP_TAG}，但路径未包含 ${CG_INTERNAL_PATH_PREFIX}；内部 HTTP 接口不得暴露给前端"
                fi
            fi

            if printf '%s\n' "$tags" | grep -Eq "前端API" && printf '%s\n' "$tags" | grep -Eq "Feign"; then
                if ! plan_allows_shared_frontend_feign; then
                    add_failure "$operation_label 同时标记 前端API 和 Feign；如确需共用，必须在 plan.md 声明共用接口例外、权限模型、字段暴露风险和兼容策略"
                fi
            fi
            if printf '%s\n' "$tags" | grep -Eq "前端API" && printf '%s\n' "$tags" | grep -Fq "$CG_INTERNAL_HTTP_TAG"; then
                add_failure "$operation_label 同时标记 前端API 和 ${CG_INTERNAL_HTTP_TAG}；内部 HTTP operation 不得与前端共用"
            fi
        done < <(extract_openapi_operations "$api_file")
    fi
}

validate_registry_file() {
    local registry_file="$1"
    local file_service
    file_service="$(basename "$registry_file" .yaml)"

    local service
    service="$(strip_quotes "$(extract_scalar "$registry_file" "service")")"
    [[ -n "$service" ]] || add_failure "$file_service registry 缺少 service 字段"
    [[ -z "$service" || "$service" == "$file_service" ]] || add_failure "$registry_file 的 service=$service 与文件名 $file_service 不一致"

    local database
    database="$(strip_quotes "$(extract_scalar "$registry_file" "database")")"
    [[ -n "$database" ]] || add_failure "$file_service registry 缺少 database 字段"

    grep -Eq "^[[:space:]]*contract_files:" "$registry_file" || add_failure "$file_service registry 缺少 contract_files"
    grep -Eq "^[[:space:]]*consumes:" "$registry_file" || add_failure "$file_service registry 缺少 consumes"
    grep -Eq "^[[:space:]]*feign:" "$registry_file" || add_failure "$file_service registry 缺少 consumes.feign"
    grep -Eq "^[[:space:]]*http:" "$registry_file" || add_failure "$file_service registry 缺少 consumes.http"
    grep -Eq "^[[:space:]]*mq:" "$registry_file" || add_failure "$file_service registry 缺少 consumes.mq"

    local api_path
    api_path="$(extract_api_path "$registry_file")"
    api_path="$(strip_quotes "$api_path")"
    if [[ -z "$api_path" ]]; then
        add_failure "$file_service registry 缺少 contract_files.api"
    else
        if [[ "$api_path" != "$file_service/"* ]]; then
            add_failure "$file_service registry 的 contract_files.api 必须指向自己的服务目录，当前为 $api_path"
        fi
        validate_api_file "$file_service" "$CONTRACTS_DIR/$api_path"
    fi

    while IFS= read -r event_path; do
        [[ -z "$event_path" || "$event_path" == "[]" ]] && continue
        if [[ "$event_path" != "$file_service/"* ]]; then
            add_failure "$file_service registry 的事件契约必须指向自己的服务目录，当前为 $event_path"
        fi
        [[ -f "$CONTRACTS_DIR/$event_path" ]] || add_failure "$file_service registry 引用的事件契约不存在：contracts/$event_path"
    done < <(extract_event_paths "$registry_file")

    while IFS= read -r status_line; do
        local status
        status="$(strip_quotes "$(trim_value "${status_line#*:}")")"
        [[ -z "$status" ]] && continue
        if ! is_valid_consumer_status "$status"; then
            add_failure "$file_service registry 使用了非法 Consumer 状态：$status（仅允许 ${CG_CONSUMER_STATUSES_CSV//,//}）"
        fi
    done < <(grep -E "^[[:space:]]*status:" "$registry_file" || true)

    while IFS= read -r path_line; do
        local contract_path
        contract_path="$(strip_quotes "$(trim_value "${path_line#*:}")")"
        [[ -z "$contract_path" ]] && continue
        [[ -f "$CONTRACTS_DIR/$contract_path" ]] || add_failure "$file_service registry 的 MQ contract_path 不存在：contracts/$contract_path"
    done < <(grep -E "^[[:space:]]*contract_path:" "$registry_file" || true)

    if grep -Eq "status:[[:space:]]*MISMATCH" "$registry_file"; then
        grep -Eq "mismatches:" "$registry_file" || add_failure "$file_service registry 存在 MISMATCH 状态但缺少 mismatches 记录"
        grep -Eq "resolution:" "$registry_file" || add_failure "$file_service registry 存在 MISMATCH 但缺少 resolution"
    fi
}

validate_consumer_file() {
    local consumer_file="$1"
    local file_consumer
    file_consumer="$(basename "$consumer_file" .yaml)"

    [[ -f "$consumer_file" ]] || { add_failure "前端消费契约不存在：${consumer_file#$REPO_ROOT/}"; return; }

    local consumer
    consumer="$(strip_quotes "$(extract_scalar "$consumer_file" "consumer")")"
    [[ -n "$consumer" ]] || add_failure "$file_consumer consumer contract 缺少 consumer 字段"
    [[ -z "$consumer" || "$consumer" == "$file_consumer" ]] || add_failure "$consumer_file 的 consumer=$consumer 与文件名 $file_consumer 不一致"

    local consumer_type
    consumer_type="$(strip_quotes "$(extract_scalar "$consumer_file" "type")")"
    [[ -n "$consumer_type" ]] || add_failure "$file_consumer consumer contract 缺少 type 字段"
    [[ -z "$consumer_type" || "$consumer_type" == "frontend" ]] || add_failure "$file_consumer consumer contract 的 type 必须为 frontend，当前为 $consumer_type"

    grep -Eq "^[[:space:]]*consumes:" "$consumer_file" || add_failure "$file_consumer consumer contract 缺少 consumes"
    grep -Eq "^[[:space:]]*http:" "$consumer_file" || add_failure "$file_consumer consumer contract 缺少 consumes.http"

    while IFS= read -r status_line; do
        local status
        status="$(strip_quotes "$(trim_value "${status_line#*:}")")"
        [[ -z "$status" ]] && continue
        if ! is_valid_consumer_status "$status"; then
            add_failure "$file_consumer consumer contract 使用了非法状态：$status（仅允许 ${CG_CONSUMER_STATUSES_CSV//,//}）"
        fi
    done < <(grep -E "^[[:space:]]*status:" "$consumer_file" || true)

    if grep -Eq "status:[[:space:]]*['\"]?MISMATCH['\"]?" "$consumer_file"; then
        grep -Eq "mismatches:" "$consumer_file" || add_failure "$file_consumer consumer contract 存在 MISMATCH 状态但缺少 mismatches 记录"
        grep -Eq "resolution:" "$consumer_file" || add_failure "$file_consumer consumer contract 存在 MISMATCH 但缺少 resolution"
    fi

    local has_entries=false
    while IFS=$'\t' read -r provider operation_id status; do
        provider="$(strip_quotes "$(trim_value "$provider")")"
        operation_id="$(strip_quotes "$(trim_value "$operation_id")")"
        status="$(strip_quotes "$(trim_value "$status")")"

        [[ -z "$provider" && -z "$operation_id" && -z "$status" ]] && continue
        has_entries=true

        [[ -n "$provider" ]] || add_failure "$file_consumer consumer contract 存在缺少 provider 的 http 消费条目"
        [[ -n "$operation_id" ]] || add_failure "$file_consumer consumer contract 消费 $provider 时缺少 operationId"
        [[ -n "$status" ]] || add_failure "$file_consumer consumer contract 消费 $provider.$operation_id 时缺少 status"

        if [[ -n "$status" ]] && ! is_valid_consumer_status "$status"; then
            add_failure "$file_consumer consumer contract 消费 $provider.$operation_id 使用了非法状态：$status（仅允许 ${CG_CONSUMER_STATUSES_CSV//,//}）"
        fi

        [[ -n "$provider" ]] || continue

        local provider_registry="$REGISTRY_DIR/$provider.yaml"
        local provider_api="$CONTRACTS_DIR/$provider/api.yaml"

        [[ -f "$provider_registry" ]] || add_failure "$file_consumer consumer contract 引用了未注册 Provider：contracts/_registry/$provider.yaml"
        [[ -f "$provider_api" ]] || { add_failure "$file_consumer consumer contract 引用了不存在的 Provider API：contracts/$provider/api.yaml"; continue; }
        [[ -n "$operation_id" ]] || continue

        local tags
        tags="$(operation_tags_for_id "$provider_api" "$operation_id" || true)"

        if [[ -z "$tags" ]]; then
            if [[ "$status" == "RESOLVED" ]]; then
                add_failure "$file_consumer consumer contract 将 $provider.$operation_id 标记为 RESOLVED，但 Provider api.yaml 未声明该 operationId"
            fi
            continue
        fi

        if printf '%s\n' "$tags" | grep -Eq "Feign"; then
            if [[ "$status" == "MISMATCH" ]]; then
                add_warning "$file_consumer consumer contract 记录了 $provider.$operation_id 指向 Feign operation 的 MISMATCH，请确认 resolution 中包含改造方案"
            else
                add_failure "$file_consumer consumer contract 不得消费 Feign operation：$provider.$operation_id"
            fi
        elif ! printf '%s\n' "$tags" | grep -Eq "前端API|外部API"; then
            add_failure "$file_consumer consumer contract 消费的 $provider.$operation_id 未标记 前端API 或 外部API，当前 tags：$tags"
        fi
    done < <(extract_consumer_http_entries "$consumer_file")

    if [[ "$has_entries" == "false" ]]; then
        add_warning "$file_consumer consumer contract 暂未声明 consumes.http 条目"
    fi
}

if [[ ${#failures[@]} -eq 0 && ${#registry_files[@]} -gt 0 ]]; then
    for registry_file in "${registry_files[@]}"; do
        validate_registry_file "$registry_file"
    done
fi

if [[ ${#failures[@]} -eq 0 && ${#consumer_files[@]} -gt 0 ]]; then
    for consumer_file in "${consumer_files[@]}"; do
        validate_consumer_file "$consumer_file"
    done
fi

if [[ -n "$PLAN_FILE" ]] && plan_mentions_microservice_contract; then
    if ! grep -Eiq "禁止跨服务直连数据库|禁止跨库|不得.*直连数据库|独立数据库|跨服务.*(Feign|MQ|接口|契约)" "$PLAN_FILE"; then
        add_failure "当前 plan 涉及微服务契约，但未声明禁止跨服务直连数据库或等价边界规则"
    fi
fi

# Run the shared YAML/OpenAPI semantic analyzer after structural checks. This
# catches schema-level drift that grep/awk checks cannot see, while keeping the
# existing shell validator as a portable first line of defense.
SEMANTIC_ANALYZER="$SCRIPT_DIR/../python/contract_analyzer.py"
if [[ ${#failures[@]} -eq 0 && -f "$SEMANTIC_ANALYZER" ]]; then
    PYTHON_BIN=""
    if command -v python3 >/dev/null 2>&1; then
        PYTHON_BIN="python3"
    elif command -v python >/dev/null 2>&1; then
        PYTHON_BIN="python"
    fi

    if [[ -z "$PYTHON_BIN" ]]; then
        add_failure "语义契约校验需要 python3/python，但当前环境未安装"
    elif ! "$PYTHON_BIN" -c 'import yaml' >/dev/null 2>&1; then
        add_failure "语义契约校验需要 PyYAML；请运行 $PYTHON_BIN -m pip install pyyaml"
    else
        semantic_args=(validate --repo-root "$REPO_ROOT")
        [[ -n "$SERVICE_FILTER" ]] && semantic_args+=(--service "$SERVICE_FILTER")
        [[ -n "$CONSUMER_FILTER" ]] && semantic_args+=(--consumer "$CONSUMER_FILTER")
        set +e
        semantic_output="$(PYTHONDONTWRITEBYTECODE=1 "$PYTHON_BIN" "$SEMANTIC_ANALYZER" "${semantic_args[@]}" 2>&1)"
        semantic_rc=$?
        set -e
        [[ -n "$semantic_output" ]] && printf '%s\n' "$semantic_output"
        if [[ $semantic_rc -eq 1 ]]; then
            add_failure "YAML/OpenAPI 语义校验失败"
        elif [[ $semantic_rc -gt 2 ]]; then
            add_failure "YAML/OpenAPI 语义校验异常退出（exit=$semantic_rc）"
        fi
    fi
fi

if [[ ${#warnings[@]} -gt 0 ]]; then
    for warning in "${warnings[@]}"; do
        echo "[contract-governance] 警告：$warning" >&2
    done
fi

if [[ ${#failures[@]} -gt 0 ]]; then
    echo "[contract-governance] 注册表校验失败" >&2
    for failure in "${failures[@]}"; do
        echo "  - $failure" >&2
    done
    echo "[contract-governance] 新项目请先运行：.specify/extensions/contract-governance/scripts/bash/init-registry.sh --service <service-name>；前端消费方运行：.specify/extensions/contract-governance/scripts/bash/init-consumer.sh --consumer <consumer-name>" >&2
    exit 1
fi

echo "[contract-governance] 注册表校验通过"
