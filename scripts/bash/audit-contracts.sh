#!/usr/bin/env bash

set -eo pipefail

SERVICE=""
CONSUMER=""
FORMAT="text"
STRICT_WARNINGS=false
RUNTIME_OPENAPI=""
EVENT_OLD=""
EVENT_NEW=""

usage() {
    cat <<'EOF'
Usage: audit-contracts.sh [options]

执行 YAML/OpenAPI 语义审计，并支持运行时 OpenAPI 和事件 schema 兼容性对比。

Options:
  --service <name>          限定 Provider 服务；runtime 模式必填
  --consumer <name>         限定前端 Consumer
  --format <text|json|sarif>  输出格式（默认 text）
  --strict-warnings         有 warning 时返回 exit 2
  --runtime-openapi <file>  将导出的运行时 OpenAPI 与 Provider 契约对比
  --event-old <file>        事件 schema 旧版本（需同时提供 --event-new）
  --event-new <file>        事件 schema 新版本（需同时提供 --event-old）
  --help, -h                显示帮助

退出码：0=通过，1=错误，2=warning 严格模式或 breaking change。
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --service) [[ $# -ge 2 ]] || { echo "ERROR: --service 需要服务名" >&2; exit 1; }; SERVICE="$2"; shift 2 ;;
        --consumer) [[ $# -ge 2 ]] || { echo "ERROR: --consumer 需要名称" >&2; exit 1; }; CONSUMER="$2"; shift 2 ;;
        --format) [[ $# -ge 2 ]] || { echo "ERROR: --format 需要值" >&2; exit 1; }; FORMAT="$2"; shift 2 ;;
        --strict-warnings) STRICT_WARNINGS=true; shift ;;
        --runtime-openapi) [[ $# -ge 2 ]] || { echo "ERROR: --runtime-openapi 需要文件" >&2; exit 1; }; RUNTIME_OPENAPI="$2"; shift 2 ;;
        --event-old) [[ $# -ge 2 ]] || { echo "ERROR: --event-old 需要文件" >&2; exit 1; }; EVENT_OLD="$2"; shift 2 ;;
        --event-new) [[ $# -ge 2 ]] || { echo "ERROR: --event-new 需要文件" >&2; exit 1; }; EVENT_NEW="$2"; shift 2 ;;
        --help|-h) usage; exit 0 ;;
        *) echo "ERROR: 未知参数 '$1'" >&2; usage >&2; exit 1 ;;
    esac
done

case "$FORMAT" in text|json|sarif) ;; *) echo "ERROR: --format 仅支持 text/json/sarif" >&2; exit 1 ;; esac

SCRIPT_DIR="$(CDPATH="" cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common-utils.sh
source "$SCRIPT_DIR/common-utils.sh"
COMMON_SH="$SCRIPT_DIR/../../../../scripts/bash/common.sh"
if [[ -f "$COMMON_SH" ]]; then
    # shellcheck source=/dev/null
    source "$COMMON_SH"
fi
REPO_ROOT="$(get_repo_root "$SCRIPT_DIR")"
ANALYZER="$SCRIPT_DIR/../python/contract_analyzer.py"

PYTHON_BIN=""
if command -v python3 >/dev/null 2>&1; then PYTHON_BIN="python3"
elif command -v python >/dev/null 2>&1; then PYTHON_BIN="python"
fi
[[ -n "$PYTHON_BIN" ]] || { echo "ERROR: contract audit 需要 python3/python" >&2; exit 1; }
"$PYTHON_BIN" -c 'import yaml' >/dev/null 2>&1 || { echo "ERROR: contract audit 需要 PyYAML；请运行 $PYTHON_BIN -m pip install pyyaml" >&2; exit 1; }

if [[ -n "$RUNTIME_OPENAPI" ]]; then
    [[ -n "$SERVICE" ]] || { echo "ERROR: --runtime-openapi 必须同时提供 --service" >&2; exit 1; }
    [[ -f "$RUNTIME_OPENAPI" ]] || { echo "ERROR: runtime OpenAPI 不存在：$RUNTIME_OPENAPI" >&2; exit 1; }
    contract_file="$REPO_ROOT/contracts/$SERVICE/api.yaml"
    [[ -f "$contract_file" ]] || { echo "ERROR: Provider 契约不存在：$contract_file" >&2; exit 1; }
    exec env PYTHONDONTWRITEBYTECODE=1 "$PYTHON_BIN" "$ANALYZER" runtime-diff \
        --contract "$contract_file" --runtime "$RUNTIME_OPENAPI" --service "$SERVICE" --format "$FORMAT"
fi

if [[ -n "$EVENT_OLD" || -n "$EVENT_NEW" ]]; then
    [[ -n "$EVENT_OLD" && -n "$EVENT_NEW" ]] || { echo "ERROR: --event-old 与 --event-new 必须同时提供" >&2; exit 1; }
    [[ -f "$EVENT_OLD" && -f "$EVENT_NEW" ]] || { echo "ERROR: 事件 schema 文件不存在" >&2; exit 1; }
    exec env PYTHONDONTWRITEBYTECODE=1 "$PYTHON_BIN" "$ANALYZER" event-diff --old "$EVENT_OLD" --new "$EVENT_NEW" --format "$FORMAT"
fi

args=(validate --repo-root "$REPO_ROOT" --format "$FORMAT")
[[ -n "$SERVICE" ]] && args+=(--service "$SERVICE")
[[ -n "$CONSUMER" ]] && args+=(--consumer "$CONSUMER")
[[ "$STRICT_WARNINGS" == "true" ]] && args+=(--strict-warnings)
exec env PYTHONDONTWRITEBYTECODE=1 "$PYTHON_BIN" "$ANALYZER" "${args[@]}"
