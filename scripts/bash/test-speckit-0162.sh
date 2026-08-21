#!/usr/bin/env bash
# Verify a real local installation with the pinned Spec Kit compatibility floor.

set -eo pipefail

SCRIPT_DIR="$(CDPATH="" cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(CDPATH="" cd "$SCRIPT_DIR/../.." && pwd)"
EXPECTED_VERSION="0.16.2"
TMP_BASE="${TMPDIR:-/tmp}"
FIXTURE_DIR=""
LOG_FILE=""

fail() {
    echo "Spec Kit 0.16.2 smoke error: $1" >&2
    if [[ -n "$LOG_FILE" && -f "$LOG_FILE" ]]; then
        cat "$LOG_FILE" >&2
    fi
    exit 1
}

cleanup() {
    if [[ -n "$FIXTURE_DIR" && -d "$FIXTURE_DIR" ]]; then
        case "$FIXTURE_DIR" in
            "$TMP_BASE"/contract-governance-speckit-0162.*)
                rm -rf "$FIXTURE_DIR"
                ;;
        esac
    fi
}

trap cleanup EXIT HUP INT TERM

command -v specify >/dev/null 2>&1 || fail "specify is not installed"
SPECIFY_CMD=(specify)
ACTUAL_VERSION="$("${SPECIFY_CMD[@]}" --version | awk 'NR == 1 { print $2 }')"
if [[ "$ACTUAL_VERSION" != "$EXPECTED_VERSION" ]]; then
    command -v uvx >/dev/null 2>&1 || \
        fail "expected specify $EXPECTED_VERSION, found ${ACTUAL_VERSION:-unknown}, and uvx is unavailable"
    SPECIFY_CMD=(uvx --from "specify-cli==$EXPECTED_VERSION" specify)
    ACTUAL_VERSION="$("${SPECIFY_CMD[@]}" --version | awk 'NR == 1 { print $2 }')"
fi
[[ "$ACTUAL_VERSION" == "$EXPECTED_VERSION" ]] || \
    fail "expected specify $EXPECTED_VERSION, found ${ACTUAL_VERSION:-unknown}"

FIXTURE_DIR="$(mktemp -d "$TMP_BASE/contract-governance-speckit-0162.XXXXXX")"
LOG_FILE="$FIXTURE_DIR/smoke.log"
cd "$FIXTURE_DIR"

"${SPECIFY_CMD[@]}" init --here --force --integration codex --ignore-agent-tools >"$LOG_FILE" 2>&1 || \
    fail "fixture initialization failed"
"${SPECIFY_CMD[@]}" extension add --dev "$ROOT_DIR" >"$LOG_FILE" 2>&1 || \
    fail "extension installation failed"

INSTALL_DIR="$FIXTURE_DIR/.specify/extensions/contract-governance"
[[ -f "$INSTALL_DIR/extension.yml" ]] || fail "installed manifest is missing"
[[ -f "$INSTALL_DIR/contract-governance-config.yml" ]] || \
    fail "optional config template was not materialized"

for forbidden in .git .github .learnings .DS_Store AGENTS.md .extensionignore; do
    [[ ! -e "$INSTALL_DIR/$forbidden" ]] || fail "ignored source artifact was installed: $forbidden"
done
[[ ! -e "$INSTALL_DIR/examples/.DS_Store" ]] || \
    fail "nested .DS_Store was installed"

python3 - "$FIXTURE_DIR" <<'PY'
import json
import sys
from pathlib import Path

import yaml

fixture = Path(sys.argv[1])
registry = json.loads(
    (fixture / ".specify/extensions/.registry").read_text(encoding="utf-8")
)
entry = registry["extensions"]["contract-governance"]
assert entry["version"] == "1.7.0", entry

registered = set(entry["registered_commands"]["codex"])
canonical = {
    "speckit.contract-governance.init",
    "speckit.contract-governance.init-consumer",
    "speckit.contract-governance.validate-boundary",
    "speckit.contract-governance.validate-registry",
    "speckit.contract-governance.diff",
    "speckit.contract-governance.check-changelog",
    "speckit.contract-governance.validate",
    "speckit.contract-governance.audit",
    "speckit.contract-governance.sync-map",
}
assert canonical <= registered, sorted(canonical - registered)
aliases = {name.replace("speckit.contract-governance.", "speckit.contract.") for name in canonical}
assert aliases <= registered, sorted(aliases - registered)
assert len(registered) == 18, sorted(registered)

for command in canonical:
    skill_name = command.replace(".", "-")
    assert (fixture / ".agents/skills" / skill_name / "SKILL.md").is_file(), skill_name
for command in aliases:
    skill_name = command.replace(".", "-")
    assert (fixture / ".agents/skills" / skill_name / "SKILL.md").is_file(), skill_name

config = yaml.safe_load(
    (fixture / ".specify/extensions/contract-governance/contract-governance-config.yml").read_text(encoding="utf-8")
)
assert config["changelog_enforcement"] == "all", config
assert config["changelog_baseline_ref"] == "", config

hooks = yaml.safe_load(
    (fixture / ".specify/extensions.yml").read_text(encoding="utf-8")
)["hooks"]
expected_hooks = {
    "after_plan": "speckit.contract-governance.validate-boundary",
    "before_tasks": "speckit.contract-governance.validate",
    "after_tasks": "speckit.contract-governance.validate",
    "after_implement": "speckit.contract-governance.check-changelog",
}
for event, command in expected_hooks.items():
    matching = [
        hook
        for hook in hooks[event]
        if hook["extension"] == "contract-governance"
    ]
    assert len(matching) == 1, (event, matching)
    assert matching[0]["command"] == command, matching[0]
    expected_priority = 5 if event == "after_implement" else 10
    assert matching[0]["priority"] == expected_priority, matching[0]
PY

"${SPECIFY_CMD[@]}" extension info contract-governance >"$LOG_FILE" 2>&1 || \
    fail "installed extension metadata cannot be read"

echo "Spec Kit 0.16.2 compatibility smoke passed"
