#!/usr/bin/env bash

set -eo pipefail

SERVICE_NAME=""
BASE_REF=""
WRITE=false
CONSUMER_FILES=()

usage() {
    cat << 'EOF'
Usage: diff-contract.sh --service <service-name> [--base <git-ref>] [--write]

对比 contracts/<service>/api.yaml 的 git 版本与当前版本，检测接口变更并生成 x-changelog。

Options:
  --service <name>  服务名，例如 my-service
  --base <ref>      Git 基线分支或 commit（默认 HEAD）
  --write           将生成的 x-changelog 追加写到 api.yaml
  --consumer <file> 同步更新指定消费者文件的 changes 段（可多次指定，必须与 --write 同时使用）
  --help, -h        显示帮助信息
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --service)
            [[ $# -ge 2 ]] || { echo "ERROR: --service 需要服务名" >&2; exit 1; }
            SERVICE_NAME="$2"
            shift 2
            ;;
        --base)
            [[ $# -ge 2 ]] || { echo "ERROR: --base 需要 git ref" >&2; exit 1; }
            BASE_REF="$2"
            shift 2
            ;;
        --write)
            WRITE=true
            shift
            ;;
        --consumer)
            [[ $# -ge 2 ]] || { echo "ERROR: --consumer 需要文件路径" >&2; exit 1; }
            CONSUMER_FILES+=("$2")
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

if [[ ${#CONSUMER_FILES[@]} -gt 0 && "$WRITE" != "true" ]]; then
    echo "ERROR: --consumer 会修改消费者契约，必须与 --write 同时使用" >&2
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
API_FILE="$CONTRACTS_DIR/$SERVICE_NAME/api.yaml"
CONSUMERS_DIR="$CONTRACTS_DIR/_consumers"

if [[ ! -f "$API_FILE" ]]; then
    echo "ERROR: 未找到 contracts/$SERVICE_NAME/api.yaml" >&2
    exit 1
fi

# ─── 提取 operation 列表 ──────────────────────────────────────────────────

extract_operations() {
    # 输入：api.yaml 文件路径（或 stdin）
    # 输出：path<TAB>method<TAB>operationId
    local file="$1"
    awk '
      function trim(s) {
        gsub(/^[[:space:]]+/, "", s)
        gsub(/[[:space:]]+$/, "", s)
        return s
      }
      function emit() {
        if (in_operation && current_path != "" && current_method != "") {
          print current_path "\t" current_method "\t" operation_id
        }
      }
      /^[[:space:]]{2}\/[^:]+:/ {
        emit()
        current_path=$1
        sub(/:$/, "", current_path)
        in_operation=0
        next
      }
      /^[[:space:]]{4}(get|post|put|delete|patch|options|head):/ {
        emit()
        current_method=$1
        sub(/:$/, "", current_method)
        operation_id=""
        in_operation=1
        next
      }
      in_operation && /^[[:space:]]{6}operationId:/ {
        operation_id=$0
        sub(/^[[:space:]]*operationId:[[:space:]]*/, "", operation_id)
        operation_id=trim(operation_id)
        next
      }
      END { emit() }
    ' "$file"
}

# ─── 提取 x-changelog 条目 ────────────────────────────────────────────────

extract_existing_changelog() {
    local file="$1"
    awk '
      /^x-changelog:/ { in_cl=1; next }
      in_cl && /^[^[:space:]#]/ { in_cl=0 }
      in_cl && /^[[:space:]]*-[[:space:]]*id:/ {
        id=$0
        sub(/^[[:space:]]*-[[:space:]]*id:[[:space:]]*/, "", id)
        gsub(/["'"'"']/, "", id)
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", id)
        print id
      }
    ' "$file"
}

# ─── 生成变更 ID ──────────────────────────────────────────────────────────

today_date() {
    date +%Y-%m-%d 2>/dev/null || echo "unknown-date"
}

generate_change_id() {
    local seq="$1"
    printf '%s-%03d' "$(today_date)" "$seq"
}

# ─── 获取旧版本 api.yaml ─────────────────────────────────────────────────

OLD_API=""
GIT_RELATIVE="contracts/$SERVICE_NAME/api.yaml"

if [[ -n "$BASE_REF" ]]; then
    OLD_API="$(git -C "$REPO_ROOT" show "$BASE_REF:$GIT_RELATIVE" 2>/dev/null || true)"
else
    OLD_API="$(git -C "$REPO_ROOT" show "HEAD:$GIT_RELATIVE" 2>/dev/null || true)"
fi

if [[ -z "$OLD_API" ]]; then
    echo "[diff-contract] contracts/$SERVICE_NAME/api.yaml 在 git 中不存在（全新契约），跳过变更检测"
    exit 0
fi

# ─── 对比 operation 列表 ─────────────────────────────────────────────────

OLD_OPS_FILE="$(mktemp)"
NEW_OPS_FILE="$(mktemp)"
OLD_KEYS_FILE="$(mktemp)"
NEW_KEYS_FILE="$(mktemp)"
REMOVED_KEYS="$(mktemp)"
ADDED_KEYS="$(mktemp)"
trap 'rm -f "$OLD_OPS_FILE" "$NEW_OPS_FILE" "$OLD_KEYS_FILE" "$NEW_KEYS_FILE" "$REMOVED_KEYS" "$ADDED_KEYS"' EXIT

echo "$OLD_API" | extract_operations /dev/stdin > "$OLD_OPS_FILE"
extract_operations "$API_FILE" > "$NEW_OPS_FILE"

# 生成排序后的 key 列表（method + path）
awk -F'\t' '{ print $2 " " $1 }' "$OLD_OPS_FILE" | sort > "$OLD_KEYS_FILE"
awk -F'\t' '{ print $2 " " $1 }' "$NEW_OPS_FILE" | sort > "$NEW_KEYS_FILE"

# 找出被删除和新增的 key
comm -23 "$OLD_KEYS_FILE" "$NEW_KEYS_FILE" > "$REMOVED_KEYS"
comm -13 "$OLD_KEYS_FILE" "$NEW_KEYS_FILE" > "$ADDED_KEYS"

# ─── 分类变更 ────────────────────────────────────────────────────────────

BREAKING_CHANGES=()
NON_BREAKING_CHANGES=()
SEQ=1

lookup_op_id() {
    # 从 ops 文件中根据 path 和 method 查找 operationId
    local ops_file="$1"
    local path="$2"
    local method="$3"
    awk -F'\t' -v p="$path" -v m="$method" '$1 == p && $2 == m { print $3; exit }' "$ops_file"
}

while IFS= read -r key; do
    [[ -z "$key" ]] && continue
    method="${key%% *}"
    path="${key#* }"
    op_id="$(lookup_op_id "$OLD_OPS_FILE" "$path" "$method")"
    change_id="$(generate_change_id "$SEQ")"
    BREAKING_CHANGES+=("$change_id|$method|$path|$op_id|operation 已删除")
    SEQ=$((SEQ + 1))
done < "$REMOVED_KEYS"

while IFS= read -r key; do
    [[ -z "$key" ]] && continue
    method="${key%% *}"
    path="${key#* }"
    op_id="$(lookup_op_id "$NEW_OPS_FILE" "$path" "$method")"
    change_id="$(generate_change_id "$SEQ")"
    NON_BREAKING_CHANGES+=("$change_id|$method|$path|$op_id|新增 operation")
    SEQ=$((SEQ + 1))
done < "$ADDED_KEYS"

# Replace the path-only classification with schema-aware OpenAPI changes. The
# legacy result above remains useful only as an implementation fallback while
# producing a clear dependency error when semantic analysis is unavailable.
SEMANTIC_ANALYZER="$SCRIPT_DIR/../python/contract_analyzer.py"
PYTHON_BIN=""
if command -v python3 >/dev/null 2>&1; then
    PYTHON_BIN="python3"
elif command -v python >/dev/null 2>&1; then
    PYTHON_BIN="python"
fi

if [[ -f "$SEMANTIC_ANALYZER" ]]; then
    [[ -n "$PYTHON_BIN" ]] || { echo "ERROR: 语义契约变更检测需要 python3/python" >&2; exit 1; }
    "$PYTHON_BIN" -c 'import yaml' >/dev/null 2>&1 || { echo "ERROR: 语义契约变更检测需要 PyYAML；请运行 $PYTHON_BIN -m pip install pyyaml" >&2; exit 1; }

    printf '%s\n' "$OLD_API" > "$OLD_OPS_FILE"
    set +e
    semantic_output="$(PYTHONDONTWRITEBYTECODE=1 "$PYTHON_BIN" "$SEMANTIC_ANALYZER" diff \
        --repo-root "$REPO_ROOT" \
        --service "$SERVICE_NAME" \
        --old-file "$OLD_OPS_FILE" \
        --new-file "$API_FILE" \
        --format tsv 2>&1)"
    semantic_rc=$?
    set -e
    if [[ $semantic_rc -ne 0 && $semantic_rc -ne 2 ]]; then
        echo "$semantic_output" >&2
        echo "ERROR: OpenAPI 语义变更检测失败" >&2
        exit 1
    fi

    BREAKING_CHANGES=()
    NON_BREAKING_CHANGES=()
    SEQ=1
    while IFS=$'\t' read -r change_type method path op_id change_code description impacted; do
        [[ -z "$change_type" ]] && continue
        change_id="$(generate_change_id "$SEQ")"
        [[ -n "$impacted" ]] && description="$description；受影响 Consumer：$impacted"
        if [[ "$change_type" == "breaking" ]]; then
            BREAKING_CHANGES+=("$change_id|$method|$path|$op_id|$description")
        else
            NON_BREAKING_CHANGES+=("$change_id|$method|$path|$op_id|$description")
        fi
        SEQ=$((SEQ + 1))
    done <<< "$semantic_output"
fi

# ─── 检查已有 changelog 避免重复 ──────────────────────────────────────────

EXISTING_IDS=()
while IFS= read -r id; do
    [[ -n "$id" ]] && EXISTING_IDS+=("$id")
done < <(extract_existing_changelog "$API_FILE")

is_existing() {
    local cid="$1"
    [[ ${#EXISTING_IDS[@]} -eq 0 ]] && return 1
    for eid in "${EXISTING_IDS[@]}"; do
        [[ "$eid" == "$cid" ]] && return 0
    done
    return 1
}

# ─── 输出报告 ────────────────────────────────────────────────────────────

if [[ ${#BREAKING_CHANGES[@]} -eq 0 && ${#NON_BREAKING_CHANGES[@]} -eq 0 ]]; then
    echo "[diff-contract] contracts/$SERVICE_NAME/api.yaml 接口无变更"
    exit 0
fi

TODAY="$(today_date)"

echo "[diff-contract] contracts/$SERVICE_NAME/api.yaml 变更检测："
echo ""

if [[ ${#BREAKING_CHANGES[@]} -gt 0 ]]; then
    echo "  Breaking changes (${#BREAKING_CHANGES[@]}):"
    for entry in "${BREAKING_CHANGES[@]}"; do
        IFS='|' read -r cid method path op_id desc <<< "$entry"
        label="$method $path"
        [[ -n "$op_id" ]] && label="$label ($op_id)"
        echo "    - [$cid] $label: $desc"
    done
fi

if [[ ${#NON_BREAKING_CHANGES[@]} -gt 0 ]]; then
    echo "  Non-breaking changes (${#NON_BREAKING_CHANGES[@]}):"
    for entry in "${NON_BREAKING_CHANGES[@]}"; do
        IFS='|' read -r cid method path op_id desc <<< "$entry"
        label="$method $path"
        [[ -n "$op_id" ]] && label="$label ($op_id)"
        echo "    - [$cid] $label: $desc"
    done
fi

# ─── 生成 x-changelog YAML ───────────────────────────────────────────────

CHANGELOG_YAML=""

generate_changelog_entries() {
    local entries=""
    local first=true

    for entry in "${BREAKING_CHANGES[@]}"; do
        IFS='|' read -r cid method path op_id desc <<< "$entry"
        is_existing "$cid" && continue
        if [[ "$first" == "true" ]]; then
            entries=""
            first=false
        fi
        entries+="  - id: \"$cid\"
    version: \"\"
    date: \"$TODAY\"
    type: breaking
    path: \"$path\"
    method: \"$method\"
    operationId: \"$op_id\"
    summary: \"$desc\"
"
    done

    for entry in "${NON_BREAKING_CHANGES[@]}"; do
        IFS='|' read -r cid method path op_id desc <<< "$entry"
        is_existing "$cid" && continue
        if [[ "$first" == "true" ]]; then
            entries=""
            first=false
        fi
        entries+="  - id: \"$cid\"
    version: \"\"
    date: \"$TODAY\"
    type: non-breaking
    path: \"$path\"
    method: \"$method\"
    operationId: \"$op_id\"
    summary: \"$desc\"
"
    done

    printf '%s' "$entries"
}

CHANGELOG_YAML="$(generate_changelog_entries)"

if [[ -z "$CHANGELOG_YAML" ]]; then
    echo ""
    echo "[diff-contract] 所有变更已存在于 x-changelog 中，无需追加"
    # 不提前退出——仍需处理 consumer 注入
else

echo ""
echo "  生成的 x-changelog 内容："
echo "  ─────────────────────────────"
echo "x-changelog:"
echo "$CHANGELOG_YAML"
echo "  ─────────────────────────────"

# ─── 写入 api.yaml ────────────────────────────────────────────────────────

if [[ "$WRITE" == "true" ]]; then
    # 如果 api.yaml 中已有 x-changelog，追加到末尾
    # 如果没有，添加 x-changelog 段
    if grep -q "^x-changelog:" "$API_FILE"; then
        # 追加到已有的 x-changelog 末尾
        awk '
          /^x-changelog:/ { in_cl=1; print; next }
          in_cl && /^[^[:space:]#]/ { in_cl=0 }
          in_cl && $0 ~ /^$/ { in_cl=0 }
          { print }
        ' "$API_FILE" > "${API_FILE}.tmp"
        # 在 x-changelog 段后追加新条目
        # 找到 x-changelog 段的结束位置
        {
            awk '
              /^x-changelog:/ { in_cl=1 }
              in_cl && /^[^[:space:]#]/ { in_cl=0 }
              in_cl && $0 ~ /^$/ { in_cl=0 }
              !in_cl { found=1 }
              found && in_cl==0 { print "INSERT_HERE"; found=0 }
              { print }
            ' "$API_FILE" | sed "/^INSERT_HERE$/i\\
$(echo "$CHANGELOG_YAML" | sed 's/\\/\\\\/g; s/&/\\&/g')
" > "${API_FILE}.tmp"
        }
        mv "${API_FILE}.tmp" "$API_FILE"
    else
        # 在文件末尾追加 x-changelog
        {
            echo ""
            echo "x-changelog:"
            echo "$CHANGELOG_YAML"
        } >> "$API_FILE"
    fi
    echo "[diff-contract] 已将 x-changelog 写入 contracts/$SERVICE_NAME/api.yaml"
fi

fi  # close CHANGELOG_YAML empty check

# ─── 生成 consumer changes 段 ────────────────────────────────────────────

if [[ ${#BREAKING_CHANGES[@]} -gt 0 ]]; then
    echo ""
    echo "  消费者需关注的 breaking changes（可追加到 _consumers/*.yaml 对应 http 条目下）："
    echo "  ─────────────────────────────────────────────────────────────────"
    echo "      changes:"
    for entry in "${BREAKING_CHANGES[@]}"; do
        IFS='|' read -r cid method path op_id desc <<< "$entry"
        echo "        - change_id: \"$cid\""
        echo "          type: breaking"
        echo "          path: \"$path\""
        echo "          method: \"$method\""
        echo "          summary: \"$desc\""
        echo "          since: \"$TODAY\""
        echo "          ack: PENDING_ACK"
    done
    echo "  ─────────────────────────────────────────────────────────────────"
fi

# ─── 写入 consumer 文件 ──────────────────────────────────────────────────

inject_consumer_changes() {
    local consumer_file="$1"
    local op_id="$2"
    local changes_tmpfile="$3"

    awk -v operation_id="$op_id" -v changes_file="$changes_tmpfile" '
      {
        lines[NR] = $0
      }
      END {
        n = NR

        # Read the changes block from the temp file
        num_changes = 0
        while ((getline cline < changes_file) > 0) {
          num_changes++
          changes_lines[num_changes] = cline
        }
        close(changes_file)

        # Step 1: find the line with matching operationId
        target = -1
        for (i = 1; i <= n; i++) {
          line = lines[i]
          tmp = line
          gsub(/^[[:space:]]+/, "", tmp)
          if (tmp ~ /^operationId:/) {
            val = tmp
            sub(/^operationId:[[:space:]]*/, "", val)
            gsub(/["'"'"']/, "", val)
            gsub(/[[:space:]]+$/, "", val)
            if (val == operation_id) {
              target = i
              break
            }
          }
        }

        if (target == -1) {
          for (i = 1; i <= n; i++) print lines[i]
          exit
        }

        # Step 2: find the end of this http entry
        entry_end = n
        for (i = target + 1; i <= n; i++) {
          line = lines[i]
          if (line ~ /^[[:space:]]*$/) continue
          leading = 0
          for (j = 1; j <= length(line); j++) {
            c = substr(line, j, 1)
            if (c == " ") leading++
            else break
          }
          if (leading <= 4) {
            entry_end = i - 1
            break
          }
        }
        while (entry_end > target && lines[entry_end] ~ /^[[:space:]]*$/) {
          entry_end--
        }

        # Step 3: check if there is already a changes: block in this entry
        has_changes = 0
        changes_start = -1
        for (i = target; i <= entry_end; i++) {
          line = lines[i]
          tmp = line
          gsub(/^[[:space:]]+/, "", tmp)
          if (tmp ~ /^changes:/) {
            has_changes = 1
            changes_start = i
            break
          }
        }

        # Step 4: print everything, injecting changes at the right place
        if (has_changes) {
          # Find end of changes block
          changes_end = entry_end
          for (i = changes_start + 1; i <= entry_end; i++) {
            line = lines[i]
            if (line ~ /^[[:space:]]*$/) continue
            leading = 0
            for (j = 1; j <= length(line); j++) {
              c = substr(line, j, 1)
              if (c == " ") leading++
              else break
            }
            tmp = line
            gsub(/^[[:space:]]+/, "", tmp)
            if (leading <= 6 && tmp !~ /^- *change_id:/) {
              changes_end = i - 1
              break
            }
          }
          for (i = 1; i <= changes_end; i++) print lines[i]
          for (k = 1; k <= num_changes; k++) print changes_lines[k]
          for (i = changes_end + 1; i <= n; i++) print lines[i]
        } else {
          for (i = 1; i <= entry_end; i++) print lines[i]
          print "      changes:"
          for (k = 1; k <= num_changes; k++) print changes_lines[k]
          for (i = entry_end + 1; i <= n; i++) print lines[i]
        }
      }
    ' "$consumer_file" > "${consumer_file}.tmp" && mv "${consumer_file}.tmp" "$consumer_file"
}

if [[ ${#CONSUMER_FILES[@]} -gt 0 && ${#BREAKING_CHANGES[@]} -gt 0 ]]; then
    CHANGES_TMP="$(mktemp)"
    trap 'rm -f "$OLD_OPS_FILE" "$NEW_OPS_FILE" "$OLD_KEYS_FILE" "$NEW_KEYS_FILE" "$REMOVED_KEYS" "$ADDED_KEYS" "$CHANGES_TMP"' EXIT

    for consumer_file in "${CONSUMER_FILES[@]}"; do
        if [[ ! -f "$consumer_file" ]]; then
            echo "[diff-contract] 警告：消费者文件不存在：$consumer_file" >&2
            continue
        fi
        for entry in "${BREAKING_CHANGES[@]}"; do
            IFS='|' read -r cid method path op_id desc <<< "$entry"
            if [[ -z "$op_id" ]]; then continue; fi
            if ! grep -q "operationId:.*$op_id" "$consumer_file"; then continue; fi

            # Write the changes YAML block to a temp file
            cat > "$CHANGES_TMP" << CHANGEEOF
        - change_id: "$cid"
          type: breaking
          path: "$path"
          method: "$method"
          summary: "$desc"
          since: "$TODAY"
          ack: PENDING_ACK
CHANGEEOF

            inject_consumer_changes "$consumer_file" "$op_id" "$CHANGES_TMP"
            echo "[diff-contract] 已将 breaking change $cid 注入到 $consumer_file 的 $op_id 条目下"
        done
    done
fi

# ─── 退出码 ───────────────────────────────────────────────────────────────

if [[ ${#BREAKING_CHANGES[@]} -gt 0 ]]; then
    exit 2  # 有 breaking changes
fi
exit 0  # 只有 non-breaking changes
