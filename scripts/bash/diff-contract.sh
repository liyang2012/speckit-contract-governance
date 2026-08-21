#!/usr/bin/env bash

set -eo pipefail

SERVICE_NAME=""
BASE_REF=""
WRITE=false
CONSUMER_FILES=()
OUTPUT_FORMAT="text"

usage() {
    cat <<'EOF'
Usage: diff-contract.sh --service <service-name> [--base <git-ref>] [--write]

检测 Provider 语义变化，按 operation 聚合生成 x-changelog。

Options:
  --service <name>  Provider 服务名
  --base <ref>      Git 比较基线（默认 HEAD）
  --write           写入 Provider api.yaml
  --consumer <file> 显式授权写入 Consumer PENDING_ACK（可重复，需配合 --write）
  --format <format> text 或 json（默认 text）
  --help, -h        显示帮助
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --service) [[ $# -ge 2 ]] || { echo "ERROR: --service 需要服务名" >&2; exit 1; }; SERVICE_NAME="$2"; shift 2 ;;
        --base) [[ $# -ge 2 ]] || { echo "ERROR: --base 需要 git ref" >&2; exit 1; }; BASE_REF="$2"; shift 2 ;;
        --write) WRITE=true; shift ;;
        --consumer) [[ $# -ge 2 ]] || { echo "ERROR: --consumer 需要文件路径" >&2; exit 1; }; CONSUMER_FILES+=("$2"); shift 2 ;;
        --format) [[ $# -ge 2 ]] || { echo "ERROR: --format 需要值" >&2; exit 1; }; OUTPUT_FORMAT="$2"; shift 2 ;;
        --help|-h) usage; exit 0 ;;
        *) echo "ERROR: 未知参数 '$1'" >&2; usage >&2; exit 1 ;;
    esac
done

[[ -n "$SERVICE_NAME" ]] || { echo "ERROR: 必须提供 --service <service-name>" >&2; exit 1; }
[[ "$SERVICE_NAME" =~ ^[A-Za-z0-9_.-]+$ ]] || { echo "ERROR: 非法服务名：$SERVICE_NAME" >&2; exit 1; }
if [[ ${#CONSUMER_FILES[@]} -gt 0 && "$WRITE" != "true" ]]; then
    echo "ERROR: --consumer 会修改 Consumer 契约，必须与 --write 同时使用" >&2
    exit 1
fi

SCRIPT_DIR="$(CDPATH="" cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common-utils.sh
source "$SCRIPT_DIR/common-utils.sh"
REPO_ROOT="$(get_repo_root "$(pwd)")"
PYTHON_CORE="$SCRIPT_DIR/../python/contract_analyzer.py"
[[ -f "$PYTHON_CORE" ]] || { echo "ERROR: Python 核心不存在：$PYTHON_CORE" >&2; exit 1; }

ARGS=(changelog --repo-root "$REPO_ROOT" --service "$SERVICE_NAME" --format "$OUTPUT_FORMAT")
[[ -n "$BASE_REF" ]] && ARGS+=(--base "$BASE_REF")
[[ "$WRITE" == "true" ]] && ARGS+=(--write)
for consumer_file in "${CONSUMER_FILES[@]}"; do
    ARGS+=(--consumer "$consumer_file")
done

exec python3 "$PYTHON_CORE" "${ARGS[@]}"
