#!/usr/bin/env bash

set -eo pipefail

CONSUMER_NAME=""
CONSUMER_TYPE="frontend"

usage() {
    cat << 'EOF'
Usage: init-consumer.sh --consumer <consumer-name> [--type frontend]

初始化根目录 contracts/_consumers/ 前端消费契约。

Options:
  --consumer <name>  消费方名称，例如 web-app
  --type <type>      消费方类型，目前仅支持 frontend；默认 frontend
  --help, -h         显示帮助信息
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --consumer)
            [[ $# -ge 2 ]] || { echo "ERROR: --consumer 需要消费方名称" >&2; exit 1; }
            CONSUMER_NAME="$2"
            shift 2
            ;;
        --type)
            [[ $# -ge 2 ]] || { echo "ERROR: --type 需要消费方类型" >&2; exit 1; }
            CONSUMER_TYPE="$2"
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

SCRIPT_DIR="$(CDPATH="" cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load configurable values from contract-governance-config.yml
# shellcheck source=common-config.sh
source "$SCRIPT_DIR/common-config.sh"

# Use config default when --consumer is omitted
if [[ -z "$CONSUMER_NAME" ]]; then
    CONSUMER_NAME="$CG_DEFAULT_CONSUMER"
    echo "[contract-governance] 使用配置文件默认 consumer：$CONSUMER_NAME"
fi

if [[ -z "$CONSUMER_NAME" ]]; then
    echo "ERROR: 必须提供 --consumer <consumer-name> 或在配置文件中设置 default_consumer" >&2
    usage >&2
    exit 1
fi

if [[ ! "$CONSUMER_NAME" =~ ^[A-Za-z0-9_.-]+$ ]]; then
    echo "ERROR: 消费方名称只能包含字母、数字、下划线、点和短横线：$CONSUMER_NAME" >&2
    exit 1
fi

if [[ "$CONSUMER_TYPE" != "frontend" ]]; then
    echo "ERROR: 当前仅支持 --type frontend" >&2
    exit 1
fi

# Load common utilities (repo root detection)
# shellcheck source=common-utils.sh
source "$SCRIPT_DIR/common-utils.sh"

COMMON_SH="$SCRIPT_DIR/../../../../scripts/bash/common.sh"
if [[ -f "$COMMON_SH" ]]; then
    # shellcheck source=/dev/null
    source "$COMMON_SH"
fi

REPO_ROOT="$(get_repo_root "$SCRIPT_DIR")"
CONTRACTS_DIR="$REPO_ROOT/contracts"
CONSUMERS_DIR="$CONTRACTS_DIR/_consumers"
CONSUMER_FILE="$CONSUMERS_DIR/$CONSUMER_NAME.yaml"
SERVICE_MAP="$CONTRACTS_DIR/SERVICE-MAP.md"

mkdir -p "$CONSUMERS_DIR"

if [[ ! -f "$SERVICE_MAP" ]]; then
    echo "[contract-governance] 警告：缺少 contracts/SERVICE-MAP.md；前端消费契约可以先创建，但 Provider 服务仍需通过 init-registry.sh 注册" >&2
fi

if [[ ! -f "$CONSUMER_FILE" ]]; then
    cat > "$CONSUMER_FILE" << EOF
# 前端消费契约：$CONSUMER_NAME
# 本文件由 $CONSUMER_NAME 的 speckit-plan 阶段维护。
# 只记录前端消费期望，不定义后端 Provider 接口；Provider 仍归 contracts/<service>/api.yaml 所属服务维护。
#
# 示例：
# consumes:
#   http:
#     - provider: my-service
#       operationId: listReleaseRecords
#       usage: 发布记录列表页
#       required_fields:
#         - id
#         - appName
#       status: PENDING
#       evidence:
#         page: src/modules/user/pages/UserList.vue
#         client: src/modules/user/services/userApi.ts
#       changes:
#         - change_id: "2026-06-05-001"
#           type: breaking
#           path: "/api/v1/releases"
#           method: "GET"
#           summary: "Response adds pagination structure"
#           since: "2026-06-05"
#           ack: PENDING_ACK   # PENDING_ACK（未适配）/ ACKNOWLEDGED（已适配）

consumer: $CONSUMER_NAME
type: $CONSUMER_TYPE

consumes:
  http: []
EOF
    echo "[contract-governance] 已创建 contracts/_consumers/$CONSUMER_NAME.yaml"
else
    echo "[contract-governance] 已存在 contracts/_consumers/$CONSUMER_NAME.yaml，未覆盖"
fi

# Keep the global navigation map discoverable for AI and human readers. This
# only adds the Consumer index row; Provider ownership remains unchanged.
if [[ -f "$SERVICE_MAP" ]] && ! grep -Fq "contracts/_consumers/$CONSUMER_NAME.yaml" "$SERVICE_MAP"; then
    if grep -Fq "## Consumers" "$SERVICE_MAP"; then
        map_tmp="$(mktemp)"
        awk -v row="| $CONSUMER_NAME | $CONSUMER_TYPE | - | \`contracts/_consumers/$CONSUMER_NAME.yaml\` |" '
          /^## Consumers/ { in_consumers=1 }
          in_consumers && /^\|[-|[:space:]]+\|$/ && !inserted {
            print
            print row
            inserted=1
            next
          }
          { print }
        ' "$SERVICE_MAP" > "$map_tmp"
        mv "$map_tmp" "$SERVICE_MAP"
    else
        cat >> "$SERVICE_MAP" << EOF

## Consumers

| Consumer | Type | Framework | Contract |
|----------|------|-----------|----------|
| $CONSUMER_NAME | $CONSUMER_TYPE | - | `contracts/_consumers/$CONSUMER_NAME.yaml` |
EOF
    fi
    echo "[contract-governance] 已将 $CONSUMER_NAME 补充到 contracts/SERVICE-MAP.md"
fi

echo "[contract-governance] 前端消费契约初始化完成：$CONSUMER_NAME ($CONSUMER_TYPE)"
