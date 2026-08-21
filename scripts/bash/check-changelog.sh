#!/usr/bin/env bash

set -eo pipefail

BASE_REF=""
SERVICES=()
CI=false
OUTPUT_FORMAT="text"

usage() {
    cat <<'EOF'
Usage: check-changelog.sh [--base <git-ref>] [--service <name>] [--ci]

校验基线后所有 Provider 语义变化均有 fingerprint 完整匹配的 x-changelog。

Options:
  --base <ref>      指定比较基线
  --service <name>  仅检查指定服务（可重复）；默认自动发现变化的 Provider
  --ci              严格模式；缺 Git、缺基线或基线不可读时失败
  --format <format> text、json 或 sarif（默认 text）
  --help, -h        显示帮助
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --base) [[ $# -ge 2 ]] || { echo "ERROR: --base 需要 git ref" >&2; exit 1; }; BASE_REF="$2"; shift 2 ;;
        --service) [[ $# -ge 2 ]] || { echo "ERROR: --service 需要服务名" >&2; exit 1; }; SERVICES+=("$2"); shift 2 ;;
        --ci) CI=true; shift ;;
        --format) [[ $# -ge 2 ]] || { echo "ERROR: --format 需要值" >&2; exit 1; }; OUTPUT_FORMAT="$2"; shift 2 ;;
        --help|-h) usage; exit 0 ;;
        *) echo "ERROR: 未知参数 '$1'" >&2; usage >&2; exit 1 ;;
    esac
done


SCRIPT_DIR="$(CDPATH="" cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common-utils.sh
source "$SCRIPT_DIR/common-utils.sh"
REPO_ROOT="$(get_repo_root "$(pwd)")"
PYTHON_CORE="$SCRIPT_DIR/../python/contract_analyzer.py"
ARGS=(check-changelog --repo-root "$REPO_ROOT" --format "$OUTPUT_FORMAT")
[[ -n "$BASE_REF" ]] && ARGS+=(--base "$BASE_REF")
[[ "$CI" == "true" ]] && ARGS+=(--ci)
for service in "${SERVICES[@]}"; do
    ARGS+=(--service "$service")
done

exec python3 "$PYTHON_CORE" "${ARGS[@]}"
