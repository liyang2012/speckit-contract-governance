#!/usr/bin/env bash
# Contract Governance extension: smoke test suite.
# Runs basic assertions against all scripts to catch regressions.
#
# Usage: test-smoke.sh
# Exit code: 0 = all pass, 1 = at least one failure.

set -eo pipefail

SCRIPT_DIR="$(CDPATH="" cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PASS=0
FAIL=0
TESTS_RUN=0

# ─── Helpers ────────────────────────────────────────────────────────────────

setup_test_dir() {
    TEST_DIR="$(mktemp -d)"
    mkdir -p "$TEST_DIR/.specify"
    cd "$TEST_DIR"
}

teardown_test_dir() {
    cd /
    rm -rf "$TEST_DIR"
}

assert_exit() {
    local label="$1" expected="$2" actual="$3"
    TESTS_RUN=$((TESTS_RUN + 1))
    if [[ "$actual" -eq "$expected" ]]; then
        echo "  PASS: $label"; PASS=$((PASS + 1))
    else
        echo "  FAIL: $label (expected exit=$expected, got exit=$actual)" >&2; FAIL=$((FAIL + 1))
    fi
}

assert_file_exists() {
    local label="$1" file="$2"
    TESTS_RUN=$((TESTS_RUN + 1))
    if [[ -f "$file" ]]; then
        echo "  PASS: $label"; PASS=$((PASS + 1))
    else
        echo "  FAIL: $label (file not found: $file)" >&2; FAIL=$((FAIL + 1))
    fi
}

assert_output_contains() {
    local label="$1" expected="$2" output="$3"
    TESTS_RUN=$((TESTS_RUN + 1))
    if echo "$output" | grep -qF "$expected"; then
        echo "  PASS: $label"; PASS=$((PASS + 1))
    else
        echo "  FAIL: $label (output missing: '$expected')" >&2; FAIL=$((FAIL + 1))
    fi
}

# Capture output + exit code without tripping set -e
capture() {
    local rc=0
    _CAPTURED_OUTPUT="$("$@" 2>&1)" || rc=$?
    _CAPTURED_RC=$rc
}

init_test_git_repo() {
    git init -q
    git add -A
    git -c user.name="Contract Governance Tests" \
        -c user.email="contract-governance-tests@example.invalid" \
        commit -q -m "init"
}

# ─── Test: --help flags ─────────────────────────────────────────────────────

echo "=== Test: --help flags ==="
for script in init-registry.sh init-consumer.sh validate-boundary.sh validate-registry.sh diff-contract.sh check-changelog.sh validate-all.sh audit-contracts.sh sync-service-map.sh; do
    capture "$SCRIPT_DIR/$script" --help
    assert_exit "$script --help exits 0" 0 $_CAPTURED_RC
done

# ─── Test: init-registry ───────────────────────────────────────────────────

echo ""
echo "=== Test: init-registry ==="
setup_test_dir

capture "$SCRIPT_DIR/init-registry.sh" --service test-svc --database db_test
assert_exit "init-registry exits 0" 0 $_CAPTURED_RC
assert_file_exists "SERVICE-MAP.md created" "$TEST_DIR/contracts/SERVICE-MAP.md"
assert_file_exists "_registry/test-svc.yaml created" "$TEST_DIR/contracts/_registry/test-svc.yaml"
assert_file_exists "test-svc/api.yaml created" "$TEST_DIR/contracts/test-svc/api.yaml"
assert_file_exists "test-svc/events/.gitkeep created" "$TEST_DIR/contracts/test-svc/events/.gitkeep"
assert_output_contains "init-registry prints success message" "初始化完成" "$_CAPTURED_OUTPUT"

TESTS_RUN=$((TESTS_RUN + 1))
if grep -q "^[[:space:]]*http: \[\]" "$TEST_DIR/contracts/_registry/test-svc.yaml"; then
    echo "  PASS: registry template contains consumes.http"; PASS=$((PASS + 1))
else
    echo "  FAIL: registry template missing consumes.http" >&2; FAIL=$((FAIL + 1))
fi

# api.yaml should contain x-changelog example comment
TESTS_RUN=$((TESTS_RUN + 1))
if grep -q "x-changelog" "$TEST_DIR/contracts/test-svc/api.yaml"; then
    echo "  PASS: api.yaml contains x-changelog example"; PASS=$((PASS + 1))
else
    echo "  FAIL: api.yaml missing x-changelog example" >&2; FAIL=$((FAIL + 1))
fi

# Run again - should not overwrite
capture "$SCRIPT_DIR/init-registry.sh" --service test-svc --database db_test
assert_output_contains "init-registry does not overwrite existing" "已存在" "$_CAPTURED_OUTPUT"

teardown_test_dir

# ─── Test: init-consumer ───────────────────────────────────────────────────

echo ""
echo "=== Test: init-consumer ==="
setup_test_dir

capture "$SCRIPT_DIR/init-consumer.sh" --consumer my-web
assert_exit "init-consumer exits 0" 0 $_CAPTURED_RC
assert_file_exists "_consumers/my-web.yaml created" "$TEST_DIR/contracts/_consumers/my-web.yaml"

TESTS_RUN=$((TESTS_RUN + 1))
if grep -q "changes:" "$TEST_DIR/contracts/_consumers/my-web.yaml"; then
    echo "  PASS: consumer yaml contains changes example"; PASS=$((PASS + 1))
else
    echo "  FAIL: consumer yaml missing changes example" >&2; FAIL=$((FAIL + 1))
fi
teardown_test_dir

# With config default (no --consumer)
setup_test_dir
capture "$SCRIPT_DIR/init-consumer.sh"
assert_exit "init-consumer with config default exits 0" 0 $_CAPTURED_RC
assert_output_contains "init-consumer uses config default" "web-app" "$_CAPTURED_OUTPUT"
teardown_test_dir

# Config loader should support project-local defaults: blocks as well as the
# extension template's top-level keys.
setup_test_dir
mkdir -p "$TEST_DIR/.specify/extensions"
cp -R "$SCRIPT_DIR/../.." "$TEST_DIR/.specify/extensions/contract-governance"
cat > "$TEST_DIR/.specify/extensions/contract-governance/contract-governance-config.yml" << 'EOF'
defaults:
  default_consumer: nested-web
  internal_path_prefix: /private/
  allowed_tags:
    - PublicAPI
    - Feign
    - InternalAPI
    - ExternalAPI
  internal_http_tag: InternalAPI
  internal_service_auth_mode: network-only
EOF
capture bash -lc "source '$TEST_DIR/.specify/extensions/contract-governance/scripts/bash/common-config.sh'; printf '%s|%s|%s|%s\n' \"\$CG_DEFAULT_CONSUMER\" \"\$CG_INTERNAL_PATH_PREFIX\" \"\$CG_ALLOWED_TAGS_CSV\" \"\$CG_INTERNAL_SERVICE_AUTH_MODE\""
assert_exit "common-config loads nested defaults block" 0 $_CAPTURED_RC
assert_output_contains "common-config reads nested default_consumer" "nested-web|/private/|PublicAPI,Feign,InternalAPI,ExternalAPI|network-only" "$_CAPTURED_OUTPUT"
teardown_test_dir

# ─── Test: validate-registry detects internal HTTP path violation ──────────

echo ""
echo "=== Test: validate-registry (internal HTTP path) ==="
setup_test_dir
cp -R "$SCRIPT_DIR/../.." "$TEST_DIR/contract-governance"
cat > "$TEST_DIR/contract-governance/contract-governance-config.yml" << 'EOF'
allowed_tags:
  - 前端API
  - Feign
  - 内部API
  - 外部API
internal_http_tag: 内部API
internal_path_prefix: /internal/
EOF
"$TEST_DIR/contract-governance/scripts/bash/init-registry.sh" --service svc-http --database db_http >/dev/null 2>&1
cat > "$TEST_DIR/contracts/svc-http/api.yaml" << 'EOF'
openapi: 3.0.3
info: { title: svc-http API, version: 0.0.1 }
paths:
  /api/v1/execute:
    post:
      operationId: execute
      tags: [内部API]
      responses:
        '202': { description: accepted }
components:
  schemas: {}
EOF

capture "$TEST_DIR/contract-governance/scripts/bash/validate-registry.sh"
assert_exit "validate-registry exits 1 on internal HTTP without /internal/" 1 $_CAPTURED_RC
assert_output_contains "detects internal HTTP path violation" "内部API" "$_CAPTURED_OUTPUT"
teardown_test_dir

# ─── Test: validate-registry rejects service auth in network-only mode ────

echo ""
echo "=== Test: validate-registry (internal service auth) ==="
setup_test_dir
mkdir -p "$TEST_DIR/.specify/extensions"
cp -R "$SCRIPT_DIR/../.." "$TEST_DIR/.specify/extensions/contract-governance"
cat > "$TEST_DIR/.specify/extensions/contract-governance/contract-governance-config.yml" << 'EOF'
allowed_tags:
  - 前端API
  - Feign
  - 内部API
  - 外部API
internal_http_tag: 内部API
internal_path_prefix: /internal/
internal_service_auth_mode: network-only
EOF
"$TEST_DIR/.specify/extensions/contract-governance/scripts/bash/init-registry.sh" --service svc-auth --database db_auth >/dev/null 2>&1
cat > "$TEST_DIR/contracts/svc-auth/api.yaml" << 'EOF'
openapi: 3.0.3
info: { title: svc-auth API, version: 0.0.1 }
paths:
  /internal/send:
    post:
      operationId: internalSend
      tags: [Feign]
      security:
        - serviceAuth: []
      responses:
        '200': { description: ok }
components:
  securitySchemes:
    serviceAuth:
      type: http
      scheme: bearer
  schemas: {}
EOF

capture "$TEST_DIR/.specify/extensions/contract-governance/scripts/bash/validate-registry.sh"
assert_exit "validate-registry exits 1 on internal service auth" 1 $_CAPTURED_RC
assert_output_contains "detects forbidden internal service auth" "internal-service-auth-forbidden" "$_CAPTURED_OUTPUT"
teardown_test_dir

# ─── Test: validate-registry on clean setup ───────────────────────────────

echo ""
echo "=== Test: validate-registry (clean) ==="
setup_test_dir
"$SCRIPT_DIR/init-registry.sh" --service svc-a --database db_a >/dev/null 2>&1
"$SCRIPT_DIR/init-consumer.sh" --consumer web-app >/dev/null 2>&1

capture "$SCRIPT_DIR/validate-registry.sh" --bootstrap-ok
assert_exit "validate-registry exits 0 on clean setup" 0 $_CAPTURED_RC
assert_output_contains "validate-registry reports pass" "注册表校验通过" "$_CAPTURED_OUTPUT"
teardown_test_dir

# ─── Test: reject derived Provider summaries in registry ─────────────────

echo ""
echo "=== Test: validate-registry (derived Provider summary) ==="
setup_test_dir
"$SCRIPT_DIR/init-registry.sh" --service svc-derived --database db_derived >/dev/null 2>&1
cat >> "$TEST_DIR/contracts/_registry/svc-derived.yaml" << 'EOF'

feign_operations: []
EOF

capture "$SCRIPT_DIR/validate-registry.sh"
assert_exit "validate-registry rejects duplicate Provider summary" 1 $_CAPTURED_RC
assert_output_contains "detects forbidden feign_operations" "不得维护重复字段 feign_operations" "$_CAPTURED_OUTPUT"
teardown_test_dir

# ─── Test: validate-registry detects bad x-changelog ──────────────────────

echo ""
echo "=== Test: validate-registry (bad x-changelog) ==="
setup_test_dir
"$SCRIPT_DIR/init-registry.sh" --service svc-b --database db_b >/dev/null 2>&1
cat >> "$TEST_DIR/contracts/svc-b/api.yaml" << 'EOF'

x-changelog:
  - id: "2026-01-01-001"
    version: ""
    date: "2026-01-01"
    type: invalid-type
    path: "/api/v1/foo"
    method: "GET"
    operationId: "getFoo"
EOF

capture "$SCRIPT_DIR/validate-registry.sh"
assert_exit "validate-registry exits 1 on bad x-changelog type" 1 $_CAPTURED_RC
assert_output_contains "detects invalid x-changelog type" "非法 type" "$_CAPTURED_OUTPUT"
teardown_test_dir

# ─── Test: validate-registry detects Feign path violation ─────────────────

echo ""
echo "=== Test: validate-registry (Feign path) ==="
setup_test_dir
"$SCRIPT_DIR/init-registry.sh" --service svc-c --database db_c >/dev/null 2>&1
cat > "$TEST_DIR/contracts/svc-c/api.yaml" << 'EOF'
openapi: 3.0.3
info:
  title: svc-c API
  version: 0.0.1
paths:
  /api/v1/items:
    get:
      operationId: listItems
      tags:
        - Feign
components:
  schemas: {}
EOF

capture "$SCRIPT_DIR/validate-registry.sh"
assert_exit "validate-registry exits 1 on Feign without /internal/" 1 $_CAPTURED_RC
assert_output_contains "detects Feign path violation" "/internal/" "$_CAPTURED_OUTPUT"
teardown_test_dir

# ─── Test: validate-boundary skips gracefully ─────────────────────────────

echo ""
echo "=== Test: validate-boundary (no feature) ==="
setup_test_dir

capture "$SCRIPT_DIR/validate-boundary.sh" --all
assert_exit "validate-boundary exits 0 when no feature dir" 0 $_CAPTURED_RC
assert_output_contains "validate-boundary reports skip" "已跳过" "$_CAPTURED_OUTPUT"
teardown_test_dir

# ─── Test: diff-contract no changes ──────────────────────────────────────

echo ""
echo "=== Test: diff-contract (no changes) ==="
setup_test_dir
"$SCRIPT_DIR/init-registry.sh" --service svc-d --database db_d >/dev/null 2>&1
init_test_git_repo

capture "$SCRIPT_DIR/diff-contract.sh" --service svc-d
assert_exit "diff-contract exits 0 with no changes" 0 $_CAPTURED_RC
assert_output_contains "diff-contract reports no changes" "没有未记录的语义变化" "$_CAPTURED_OUTPUT"

capture "$SCRIPT_DIR/diff-contract.sh" --service svc-d --consumer "$TEST_DIR/contracts/_consumers/web-app.yaml"
assert_exit "diff-contract rejects consumer writes without --write" 1 $_CAPTURED_RC
assert_output_contains "diff-contract explains consumer write guard" "必须与 --write 同时使用" "$_CAPTURED_OUTPUT"
teardown_test_dir

# ─── Test: diff-contract detects breaking change ─────────────────────────

echo ""
echo "=== Test: diff-contract (breaking change) ==="
setup_test_dir
"$SCRIPT_DIR/init-registry.sh" --service svc-e --database db_e >/dev/null 2>&1
cat > "$TEST_DIR/contracts/svc-e/api.yaml" << 'EOF'
openapi: 3.0.3
info:
  title: svc-e API
  version: 0.0.1
paths:
  /api/v1/orders:
    get:
      operationId: listOrders
      tags:
        - 前端API
components:
  schemas: {}
EOF
init_test_git_repo
# Remove the operation (breaking change)
cat > "$TEST_DIR/contracts/svc-e/api.yaml" << 'EOF'
openapi: 3.0.3
info:
  title: svc-e API
  version: 0.0.2
paths: {}
components:
  schemas: {}
EOF

capture "$SCRIPT_DIR/diff-contract.sh" --service svc-e
assert_exit "diff-contract exits 2 on breaking change" 2 $_CAPTURED_RC
assert_output_contains "diff-contract reports breaking" "type: breaking" "$_CAPTURED_OUTPUT"
teardown_test_dir

# ─── Test: validate-all orchestrates ─────────────────────────────────────

echo ""
echo "=== Test: validate-all ==="
setup_test_dir
"$SCRIPT_DIR/init-registry.sh" --service svc-f --database db_f >/dev/null 2>&1

capture "$SCRIPT_DIR/validate-all.sh" --bootstrap-ok
assert_exit "validate-all exits 0 on clean setup" 0 $_CAPTURED_RC
assert_output_contains "validate-all reports pass" "综合校验通过" "$_CAPTURED_OUTPUT"
teardown_test_dir

# ─── Test: semantic analyzer unit suite ──────────────────────────────────

echo ""
echo "=== Test: semantic analyzer ==="
capture env PYTHONDONTWRITEBYTECODE=1 python3 "$SCRIPT_DIR/../python/test_contract_analyzer.py"
assert_exit "semantic analyzer unit suite exits 0" 0 $_CAPTURED_RC
assert_output_contains "semantic analyzer unit suite passes" "OK" "$_CAPTURED_OUTPUT"

# ─── Test: schema-aware diff ──────────────────────────────────────────────

echo ""
echo "=== Test: diff-contract (response field removed) ==="
setup_test_dir
"$SCRIPT_DIR/init-registry.sh" --service svc-schema --database db_schema >/dev/null 2>&1
cat > "$TEST_DIR/contracts/svc-schema/api.yaml" << 'EOF'
openapi: 3.0.3
info:
  title: svc-schema API
  version: 1.0.0
paths:
  /api/v1/items:
    get:
      operationId: listItems
      tags: [前端API]
      responses:
        "200":
          description: ok
          content:
            application/json:
              schema:
                $ref: '#/components/schemas/ItemResult'
components:
  schemas:
    ItemResult:
      type: object
      properties:
        id: { type: integer }
        name: { type: string }
EOF
init_test_git_repo
python3 - "$TEST_DIR/contracts/svc-schema/api.yaml" << 'PY'
import sys, yaml
path = sys.argv[1]
with open(path, encoding="utf-8") as handle:
    data = yaml.safe_load(handle)
del data["components"]["schemas"]["ItemResult"]["properties"]["name"]
with open(path, "w", encoding="utf-8") as handle:
    yaml.safe_dump(data, handle, allow_unicode=True, sort_keys=False)
PY

capture "$SCRIPT_DIR/diff-contract.sh" --service svc-schema
assert_exit "diff-contract exits 2 when response field is removed" 2 $_CAPTURED_RC
assert_output_contains "diff-contract reports removed response field" "响应字段已删除" "$_CAPTURED_OUTPUT"
teardown_test_dir

# ─── Test: forced changelog coverage and idempotent write ────────────────

echo ""
echo "=== Test: check-changelog enforcement ==="
setup_test_dir
"$SCRIPT_DIR/init-registry.sh" --service svc-gate --database db_gate >/dev/null 2>&1
cat > "$TEST_DIR/contracts/svc-gate/api.yaml" << 'EOF'
openapi: 3.0.3
info:
  title: svc-gate API
  version: 1.0.0
paths:
  /api/v1/items:
    get:
      operationId: listItems
      tags: [前端API]
      responses:
        "200":
          description: ok
          content:
            application/json:
              schema:
                type: object
                properties:
                  id: {type: integer}
                  name: {type: string}
components:
  schemas: {}
EOF
init_test_git_repo
python3 - "$TEST_DIR/contracts/svc-gate/api.yaml" << 'PY'
import sys, yaml
path = sys.argv[1]
with open(path, encoding="utf-8") as handle:
    data = yaml.safe_load(handle)
del data["paths"]["/api/v1/items"]["get"]["responses"]["200"]["content"]["application/json"]["schema"]["properties"]["name"]
with open(path, "w", encoding="utf-8") as handle:
    yaml.safe_dump(data, handle, allow_unicode=True, sort_keys=False)
PY

capture "$SCRIPT_DIR/check-changelog.sh" --base HEAD --service svc-gate --ci
assert_exit "check-changelog exits 2 when changelog is missing" 2 $_CAPTURED_RC
assert_output_contains "check-changelog reports missing fingerprint" "changelog-coverage-missing" "$_CAPTURED_OUTPUT"

capture "$SCRIPT_DIR/diff-contract.sh" --service svc-gate --base HEAD --write
assert_exit "diff-contract write preserves breaking exit" 2 $_CAPTURED_RC
capture python3 -c 'import sys,yaml; data=yaml.safe_load(open(sys.argv[1], encoding="utf-8")); assert len(data["x-changelog"]) == 1; assert len(data["x-changelog"][0]["changes"]) == 1' "$TEST_DIR/contracts/svc-gate/api.yaml"
assert_exit "written x-changelog is valid grouped YAML" 0 $_CAPTURED_RC

capture "$SCRIPT_DIR/check-changelog.sh" --base HEAD --service svc-gate --ci
assert_exit "check-changelog passes complete coverage" 0 $_CAPTURED_RC
assert_output_contains "check-changelog reports complete coverage" "changelog-coverage-complete" "$_CAPTURED_OUTPUT"

capture "$SCRIPT_DIR/diff-contract.sh" --service svc-gate --base HEAD --write
assert_exit "second diff write keeps breaking exit" 2 $_CAPTURED_RC
assert_output_contains "second diff write is idempotent" "没有未记录的语义变化" "$_CAPTURED_OUTPUT"
capture python3 -c 'import sys,yaml; data=yaml.safe_load(open(sys.argv[1], encoding="utf-8")); assert len(data["x-changelog"]) == 1' "$TEST_DIR/contracts/svc-gate/api.yaml"
assert_exit "second diff write does not duplicate entry" 0 $_CAPTURED_RC

python3 - "$TEST_DIR/contracts/svc-gate/api.yaml" << 'PY'
import sys, yaml
path = sys.argv[1]
with open(path, encoding="utf-8") as handle:
    data = yaml.safe_load(handle)
data["paths"]["/api/v1/items"]["get"]["responses"]["202"] = {"description": "accepted: later"}
with open(path, "w", encoding="utf-8") as handle:
    yaml.safe_dump(data, handle, allow_unicode=True, sort_keys=False)
PY
capture "$SCRIPT_DIR/diff-contract.sh" --service svc-gate --base HEAD --write
assert_exit "same-day incremental non-breaking write succeeds" 2 $_CAPTURED_RC
capture python3 -c 'import sys,yaml; data=yaml.safe_load(open(sys.argv[1], encoding="utf-8")); assert len(data["x-changelog"]) == 2; assert len({e["id"] for e in data["x-changelog"]}) == 2' "$TEST_DIR/contracts/svc-gate/api.yaml"
assert_exit "same-day entries use collision-resistant IDs" 0 $_CAPTURED_RC

capture "$SCRIPT_DIR/check-changelog.sh" --ci
assert_exit "CI without configured or explicit baseline exits 1" 1 $_CAPTURED_RC
assert_output_contains "CI reports missing baseline" "changelog-baseline-missing" "$_CAPTURED_OUTPUT"
teardown_test_dir

# ─── Test: structured audit and map preview ───────────────────────────────

echo ""
echo "=== Test: structured audit ==="
setup_test_dir
"$SCRIPT_DIR/init-registry.sh" --service svc-report --database db_report >/dev/null 2>&1
capture "$SCRIPT_DIR/audit-contracts.sh" --format json
assert_exit "audit-contracts JSON exits 0" 0 $_CAPTURED_RC
assert_output_contains "audit-contracts emits JSON summary" '"summary"' "$_CAPTURED_OUTPUT"
capture "$SCRIPT_DIR/sync-service-map.sh"
assert_exit "sync-service-map preview exits 0" 0 $_CAPTURED_RC
assert_output_contains "sync-service-map previews provider" "svc-report" "$_CAPTURED_OUTPUT"
teardown_test_dir

# ─── Summary ──────────────────────────────────────────────────────────────

echo ""
echo "═══════════════════════════════════"
echo "  Total: $TESTS_RUN | Pass: $PASS | Fail: $FAIL"
echo "═══════════════════════════════════"

if [[ $FAIL -gt 0 ]]; then
    exit 1
fi
echo "  All smoke tests passed."
exit 0
