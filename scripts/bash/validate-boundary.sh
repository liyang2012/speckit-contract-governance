#!/usr/bin/env bash

set -eo pipefail

MODE="all"
FEATURE_DIR_ARG=""

usage() {
    cat << 'EOF'
Usage: validate-boundary.sh [--plan|--tasks|--all] [--feature-dir <path>]

校验当前 Spec Kit feature 的 FE/BE/Contract 边界。

Options:
  --plan                只校验 plan.md
  --tasks               只校验 tasks.md
  --all                 校验已存在的 plan.md 和 tasks.md
  --feature-dir <path>  校验指定 feature 目录
  --help, -h            显示帮助信息
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --plan)
            MODE="plan"
            shift
            ;;
        --tasks)
            MODE="tasks"
            shift
            ;;
        --all)
            MODE="all"
            shift
            ;;
        --feature-dir)
            [[ $# -ge 2 ]] || { echo "ERROR: --feature-dir 需要一个路径" >&2; exit 1; }
            FEATURE_DIR_ARG="$2"
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

# Load common utilities (repo root detection, feature dir resolution, string helpers)
# shellcheck source=common-utils.sh
source "$SCRIPT_DIR/common-utils.sh"

# Load configurable values from contract-governance-config.yml
# shellcheck source=common-config.sh
source "$SCRIPT_DIR/common-config.sh"

# Try to load project-level common.sh if available (provides get_repo_root override)
COMMON_SH="$SCRIPT_DIR/../../../../scripts/bash/common.sh"
if [[ -f "$COMMON_SH" ]]; then
    # shellcheck source=/dev/null
    source "$COMMON_SH"
fi

REPO_ROOT="$(get_repo_root "$SCRIPT_DIR")"

FEATURE_DIR="$(resolve_feature_dir "$FEATURE_DIR_ARG" "$REPO_ROOT" || true)"
if [[ -z "$FEATURE_DIR" || ! -d "$FEATURE_DIR" ]]; then
    echo "[contract-governance] 未找到 active feature 目录，已跳过边界校验"
    exit 0
fi

PLAN_FILE="$FEATURE_DIR/plan.md"
TASKS_FILE="$FEATURE_DIR/tasks.md"

failures=()
warnings=()

add_failure() {
    failures+=("$1")
}

add_warning() {
    warnings+=("$1")
}

contains_any() {
    local file="$1"
    shift
    local pattern
    for pattern in "$@"; do
        if grep -Eiq "$pattern" "$file"; then
            return 0
        fi
    done
    return 1
}

contains_literal_any() {
    local file="$1"
    shift
    local pattern
    for pattern in "$@"; do
        if grep -Fq "$pattern" "$file"; then
            return 0
        fi
    done
    return 1
}

has_unresolved_template_text() {
    local file="$1"
    contains_literal_any "$file" \
        "[FEATURE]" \
        "[FEATURE NAME]" \
        "[###-feature" \
        "[service-name]" \
        "[module-name]" \
        "[path]" \
        "[endpoint" \
        "[Title]" \
        "[language]" \
        "[framework]" \
        "NEEDS CLARIFICATION" \
        "TXXX"
}

# Build frontend keyword suffix from config (comma-separated -> pipe-separated)
_FRONTEND_KW_SUFFIX=""
if [[ -n "${CG_FRONTEND_KEYWORDS:-}" ]]; then
    _FRONTEND_KW_SUFFIX="|${CG_FRONTEND_KEYWORDS//,/|}"
fi

plan_mentions_frontend() {
    [[ -f "$PLAN_FILE" ]] || return 1
    contains_any "$PLAN_FILE" "frontend|front-end|\\bFE\\b|前端|Vue|Vite|React|Playwright${_FRONTEND_KW_SUFFIX}"
}

plan_mentions_backend() {
    [[ -f "$PLAN_FILE" ]] || return 1
    contains_any "$PLAN_FILE" "backend|back-end|\\bBE\\b|后端|Spring|微服务|controller|service|mapper|Gradle|JUnit|Feign"
}

plan_mentions_contract() {
    [[ -f "$PLAN_FILE" ]] || return 1
    contains_any "$PLAN_FILE" "contracts/|api\\.yaml|openapi|_consumers|消费契约|_consumers/[A-Za-z0-9_.-]+\\.yaml|接口契约|Provider|Consumer|PENDING|RESOLVED|Result<|PageResult<|错误码|Feign|DTO|ViewModel|FormModel"
}

tasks_mentions_frontend() {
    [[ -f "$TASKS_FILE" ]] || return 1
    contains_any "$TASKS_FILE" "\\[FE\\]|frontend|front-end|前端|Vue|Vite|React|Playwright|\\.vue|\\.ts${_FRONTEND_KW_SUFFIX}"
}

tasks_mentions_backend() {
    [[ -f "$TASKS_FILE" ]] || return 1
    contains_any "$TASKS_FILE" "\\[BE\\]|backend|back-end|后端|Spring|controller|service|manager|mapper|repository|Gradle|JUnit|Feign|src/main/java|src/test/java"
}

tasks_mentions_contract() {
    [[ -f "$TASKS_FILE" ]] || return 1
    contains_any "$TASKS_FILE" "\\[Contract\\]|contracts/|api\\.yaml|openapi|_consumers|消费契约|_consumers/[A-Za-z0-9_.-]+\\.yaml|接口契约|契约测试|Provider|Consumer|PENDING|RESOLVED|DTO|ViewModel|FormModel"
}

plan_mentions_feign_internal() {
    [[ -f "$PLAN_FILE" ]] || return 1
    contains_any "$PLAN_FILE" "Feign|/internal/|内部接口|服务间|服务调用|前端不可访问|不暴露给前端"
}

tasks_mentions_gateway_or_access_control() {
    [[ -f "$TASKS_FILE" ]] || return 1
    contains_any "$TASKS_FILE" "网关|访问控制|内部接口|前端不可访问|不暴露给前端|internal|Gateway|gateway|Nginx|路由|鉴权|服务间认证|认证透传|traceId"
}

validate_plan() {
    if [[ ! -f "$PLAN_FILE" ]]; then
        add_failure "未找到 plan.md：$PLAN_FILE"
        return
    fi

    if has_unresolved_template_text "$PLAN_FILE"; then
        add_failure "plan.md 存在未替换模板占位符或 NEEDS CLARIFICATION 标记"
    fi

    contains_any "$PLAN_FILE" "Upstream Dependencies|上游依赖" \
        || add_failure "plan.md 必须声明 Upstream Dependencies / 上游依赖"

    contains_any "$PLAN_FILE" "测试策略|完成定义|test strategy|definition of done" \
        || add_failure "plan.md 必须包含测试策略和完成定义"

    local fe=false
    local be=false
    local contract=false

    plan_mentions_frontend && fe=true
    plan_mentions_backend && be=true
    plan_mentions_contract && contract=true

    if [[ "$fe" == "true" && "$be" == "true" && "$contract" != "true" ]]; then
        add_failure "plan.md 同时涉及前端和后端，但没有声明 Contract / 接口契约边界"
    fi

    if [[ "$contract" == "true" ]]; then
        if [[ ! -d "$REPO_ROOT/contracts" ]]; then
            add_warning "plan.md 引用了 contracts，但仓库根目录缺少 contracts/ 注册表；全新项目请先运行 contract-governance 初始化命令"
        fi
        if [[ ! -f "$REPO_ROOT/contracts/SERVICE-MAP.md" ]]; then
            add_warning "plan.md 引用了 contracts，但缺少 contracts/SERVICE-MAP.md；全新项目请先运行 contract-governance 初始化命令"
        fi
        contains_any "$PLAN_FILE" "contracts/[A-Za-z0-9_.-]+/api\\.yaml|contracts/_registry/[A-Za-z0-9_.-]+\\.yaml|contracts/_consumers/[A-Za-z0-9_.-]+\\.yaml|specs/.*/contracts|contracts/" \
            || add_failure "plan.md 的契约部分必须引用明确的 contracts/ 路径"
    fi

    if [[ "$fe" != "true" && "$be" != "true" ]]; then
        add_warning "plan.md 未明确出现前端或后端范围"
    fi
}

validate_tasks() {
    if [[ ! -f "$TASKS_FILE" ]]; then
        add_failure "未找到 tasks.md：$TASKS_FILE"
        return
    fi

    if has_unresolved_template_text "$TASKS_FILE"; then
        add_failure "tasks.md 存在未替换模板占位符"
    fi

    contains_any "$TASKS_FILE" "^- \\[ \\] T[0-9]{3}" \
        || add_failure "tasks.md 必须使用 Spec Kit 标准任务编号格式，例如 '- [ ] T001 ...'"

    tasks_mentions_contract \
        || add_failure "tasks.md 必须包含可执行的契约任务或契约测试任务"

    contains_any "$TASKS_FILE" "test|测试|验证|Playwright|JUnit|pytest|契约测试|灰盒|E2E|quickstart" \
        || add_failure "tasks.md 必须包含验证或测试任务"

    contains_any "$TASKS_FILE" "Downstream Contract|下游契约|delivery-note|archive 摘要|交付摘要" \
        || add_failure "tasks.md 必须包含写明 Downstream Contract / 下游契约的最终交付任务"

    if plan_mentions_frontend && ! tasks_mentions_frontend; then
        add_failure "plan.md 将前端纳入范围，但 tasks.md 没有前端任务或路径"
    fi

    if plan_mentions_backend && ! tasks_mentions_backend; then
        add_failure "plan.md 将后端纳入范围，但 tasks.md 没有后端任务或路径"
    fi

    if plan_mentions_contract && ! tasks_mentions_contract; then
        add_failure "plan.md 声明了契约，但 tasks.md 没有契约任务或路径"
    fi

    if plan_mentions_feign_internal && ! tasks_mentions_gateway_or_access_control; then
        add_failure "plan.md 涉及 Feign/internal 接口，但 tasks.md 缺少网关、访问控制、内部接口隔离或服务间认证任务"
    fi
}

case "$MODE" in
    plan)
        validate_plan
        ;;
    tasks)
        validate_tasks
        ;;
    all)
        [[ -f "$PLAN_FILE" ]] && validate_plan || add_warning "未找到 plan.md，已跳过 plan 校验"
        [[ -f "$TASKS_FILE" ]] && validate_tasks || add_warning "未找到 tasks.md，已跳过 tasks 校验"
        ;;
esac

if [[ ${#warnings[@]} -gt 0 ]]; then
    for warning in "${warnings[@]}"; do
        echo "[contract-governance] 警告：$warning" >&2
    done
fi

if [[ ${#failures[@]} -gt 0 ]]; then
    echo "[contract-governance] 边界校验失败：$FEATURE_DIR" >&2
    for failure in "${failures[@]}"; do
        echo "  - $failure" >&2
    done
    echo "[contract-governance] 建议：先补齐 Contract 边界，再拆 FE/BE 实现任务。" >&2
    exit 1
fi

echo "[contract-governance] 边界校验通过：$FEATURE_DIR ($MODE)"
