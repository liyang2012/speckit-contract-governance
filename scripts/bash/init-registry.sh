#!/usr/bin/env bash

set -eo pipefail

SERVICE_NAME=""
DATABASE_NAME=""

usage() {
    cat << 'EOF'
Usage: init-registry.sh --service <service-name> [--database <database-name>]

初始化根目录 contracts/ 微服务契约注册表。

Options:
  --service <name>    服务名，例如 my-service
  --database <name>   数据库名，例如 db_devops；未提供时根据服务名推导
  --help, -h          显示帮助信息
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --service)
            [[ $# -ge 2 ]] || { echo "ERROR: --service 需要服务名" >&2; exit 1; }
            SERVICE_NAME="$2"
            shift 2
            ;;
        --database)
            [[ $# -ge 2 ]] || { echo "ERROR: --database 需要数据库名" >&2; exit 1; }
            DATABASE_NAME="$2"
            shift 2
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

if [[ -z "$SERVICE_NAME" ]]; then
    echo "ERROR: 必须提供 --service <service-name>" >&2
    usage >&2
    exit 1
fi

if [[ ! "$SERVICE_NAME" =~ ^[A-Za-z0-9_.-]+$ ]]; then
    echo "ERROR: 服务名只能包含字母、数字、下划线、点和短横线：$SERVICE_NAME" >&2
    exit 1
fi

SCRIPT_DIR="$(CDPATH="" cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load common utilities (repo root detection)
# shellcheck source=common-utils.sh
source "$SCRIPT_DIR/common-utils.sh"

# Try to load project-level common.sh if available (provides get_repo_root override)
COMMON_SH="$SCRIPT_DIR/../../../../scripts/bash/common.sh"
if [[ -f "$COMMON_SH" ]]; then
    # shellcheck source=/dev/null
    source "$COMMON_SH"
fi

REPO_ROOT="$(get_repo_root "$SCRIPT_DIR")"
CONTRACTS_DIR="$REPO_ROOT/contracts"
REGISTRY_DIR="$CONTRACTS_DIR/_registry"
SERVICE_DIR="$CONTRACTS_DIR/$SERVICE_NAME"
EVENTS_DIR="$SERVICE_DIR/events"

if [[ -z "$DATABASE_NAME" ]]; then
    base="${SERVICE_NAME%-service}"
    base="${base//-/_}"
    base="${base//./_}"
    DATABASE_NAME="db_$base"
fi

mkdir -p "$REGISTRY_DIR" "$EVENTS_DIR"

SERVICE_MAP="$CONTRACTS_DIR/SERVICE-MAP.md"
if [[ ! -f "$SERVICE_MAP" ]]; then
    cat > "$SERVICE_MAP" << EOF
# 微服务契约拓扑

> 本文件是所有微服务间契约的全局索引。
> 各服务的详细契约数据存储在 \`_registry/<service>.yaml\` 中，由对应服务独占写入。

## 服务注册文件

| 服务 | Registry 文件 | 契约目录 |
|------|-------------|---------|
| $SERVICE_NAME | [\`_registry/$SERVICE_NAME.yaml\`](_registry/$SERVICE_NAME.yaml) | \`contracts/$SERVICE_NAME/\` |

## 服务清单

| 服务 | 数据库 | 核心职责 | 契约状态 |
|------|--------|---------|---------|
| $SERVICE_NAME | $DATABASE_NAME | 待填写 | EMPTY |

## Consumers

| Consumer | Type | Framework | Contract |
|----------|------|-----------|----------|

## 契约变更规则

1. 每个服务只写自己的 \`_registry/<service>.yaml\` 和 \`contracts/<service>/\`。
2. Provider 在自己的 \`api.yaml\` 或 \`events/\` 中定义端点和事件。
3. Consumer 在自己的 registry 的 \`consumes.feign\`、\`consumes.http\` 或 \`consumes.mq\` 中声明期望。
4. Consumer 状态只允许 \`PENDING\`、\`RESOLVED\`、\`MISMATCH\`。
5. 微服务之间禁止跨服务直连数据库。
EOF
    echo "[contract-governance] 已创建 contracts/SERVICE-MAP.md"
elif ! grep -Eq "\\|[[:space:]]*$SERVICE_NAME[[:space:]]*\\|" "$SERVICE_MAP"; then
    echo "[contract-governance] 提示：contracts/SERVICE-MAP.md 已存在，请在服务注册文件和服务清单中补充 $SERVICE_NAME" >&2
fi

REGISTRY_FILE="$REGISTRY_DIR/$SERVICE_NAME.yaml"
if [[ ! -f "$REGISTRY_FILE" ]]; then
    cat > "$REGISTRY_FILE" << EOF
# 服务注册：$SERVICE_NAME
# 本文件由 $SERVICE_NAME 的 speckit-plan 阶段写入，仅 $SERVICE_NAME 有权修改
# provides 数据从 contract_files 自动推导，无需手动维护

service: $SERVICE_NAME
database: $DATABASE_NAME

contract_files:
  api: $SERVICE_NAME/api.yaml
  events: []

consumes:
  feign: []
  http: []
  mq: []
EOF
    echo "[contract-governance] 已创建 contracts/_registry/$SERVICE_NAME.yaml"
else
    echo "[contract-governance] 已存在 contracts/_registry/$SERVICE_NAME.yaml，未覆盖"
fi

API_FILE="$SERVICE_DIR/api.yaml"
if [[ ! -f "$API_FILE" ]]; then
    cat > "$API_FILE" << EOF
openapi: 3.0.3
info:
  title: $SERVICE_NAME API 契约
  description: |
    $SERVICE_NAME 对外提供的接口。
    状态：EMPTY — 等待 feature plan 填充。
  version: 0.0.0

# 契约变更记录（由 diff-contract.sh 自动生成，也可手动维护）
# 示例：
# x-changelog:
#   - id: "2026-06-05-001"
#     version: "1.1.0"
#     date: "2026-06-05"
#     type: breaking          # breaking / non-breaking / deprecated
#     path: "/api/v1/users"
#     method: "GET"
#     operationId: "listUsers"
#     summary: "Response structure adds pagination fields"

paths: {}

components:
  schemas: {}
EOF
    echo "[contract-governance] 已创建 contracts/$SERVICE_NAME/api.yaml"
else
    echo "[contract-governance] 已存在 contracts/$SERVICE_NAME/api.yaml，未覆盖"
fi

touch "$EVENTS_DIR/.gitkeep"
echo "[contract-governance] 已准备 contracts/$SERVICE_NAME/events/"
echo "[contract-governance] 初始化完成：$SERVICE_NAME ($DATABASE_NAME)"
