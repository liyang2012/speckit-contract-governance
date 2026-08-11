#!/usr/bin/env bash

set -eo pipefail

WRITE=false

usage() {
    cat <<'EOF'
Usage: sync-service-map.sh [--write]

根据项目配置、_registry 和 _consumers 生成 SERVICE-MAP.md。
默认只输出预览；只有显式 --write 才写入文件。

Options:
  --write     写入 contracts/SERVICE-MAP.md
  --help, -h  显示帮助
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --write) WRITE=true; shift ;;
        --help|-h) usage; exit 0 ;;
        *) echo "ERROR: 未知参数 '$1'" >&2; usage >&2; exit 1 ;;
    esac
done

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
[[ -n "$PYTHON_BIN" ]] || { echo "ERROR: SERVICE-MAP 同步需要 python3/python" >&2; exit 1; }
"$PYTHON_BIN" -c 'import yaml' >/dev/null 2>&1 || { echo "ERROR: SERVICE-MAP 同步需要 PyYAML；请运行 $PYTHON_BIN -m pip install pyyaml" >&2; exit 1; }

args=(service-map --repo-root "$REPO_ROOT")
[[ "$WRITE" == "true" ]] && args+=(--write)
exec env PYTHONDONTWRITEBYTECODE=1 "$PYTHON_BIN" "$ANALYZER" "${args[@]}"
