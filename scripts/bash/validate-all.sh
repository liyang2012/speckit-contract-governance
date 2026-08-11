#!/usr/bin/env bash

set -eo pipefail

PHASE="all"
FEATURE_DIR_ARG=""
BOOTSTRAP_OK=false

usage() {
    cat << 'EOF'
Usage: validate-all.sh [--phase plan|tasks|all] [--feature-dir <path>] [--bootstrap-ok]

运行契约治理综合校验：FE/BE/Contract 边界 + 微服务契约注册表 + 前端消费契约。

Options:
  --phase <phase>       校验阶段：plan、tasks、all；默认 all
  --feature-dir <path>  校验指定 feature 目录
  --bootstrap-ok        contracts/ 不存在时允许 registry 校验跳过
  --help, -h            显示帮助信息
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --phase)
            [[ $# -ge 2 ]] || { echo "ERROR: --phase 需要 plan、tasks 或 all" >&2; exit 1; }
            PHASE="$2"
            shift 2
            ;;
        --feature-dir)
            [[ $# -ge 2 ]] || { echo "ERROR: --feature-dir 需要路径" >&2; exit 1; }
            FEATURE_DIR_ARG="$2"
            shift 2
            ;;
        --bootstrap-ok)
            BOOTSTRAP_OK=true
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

case "$PHASE" in
    plan|tasks|all) ;;
    *)
        echo "ERROR: --phase 只能是 plan、tasks 或 all，当前为 $PHASE" >&2
        exit 1
        ;;
esac

SCRIPT_DIR="$(CDPATH="" cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

boundary_args=()
registry_args=()

case "$PHASE" in
    plan)
        boundary_args+=(--plan)
        ;;
    tasks)
        boundary_args+=(--tasks)
        ;;
    all)
        boundary_args+=(--all)
        ;;
esac

if [[ -n "$FEATURE_DIR_ARG" ]]; then
    boundary_args+=(--feature-dir "$FEATURE_DIR_ARG")
    registry_args+=(--feature-dir "$FEATURE_DIR_ARG")
fi

if [[ "$BOOTSTRAP_OK" == "true" ]]; then
    registry_args+=(--bootstrap-ok)
fi

if [[ ${#boundary_args[@]} -gt 0 ]]; then
    "$SCRIPT_DIR/validate-boundary.sh" "${boundary_args[@]}"
else
    "$SCRIPT_DIR/validate-boundary.sh"
fi

if [[ ${#registry_args[@]} -gt 0 ]]; then
    "$SCRIPT_DIR/validate-registry.sh" "${registry_args[@]}"
else
    "$SCRIPT_DIR/validate-registry.sh"
fi

echo "[contract-governance] 综合校验通过 ($PHASE)"
