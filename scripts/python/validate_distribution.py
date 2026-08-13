#!/usr/bin/env python3
"""Validate the standalone extension distribution before release."""

from __future__ import annotations

import re
import sys
from pathlib import Path

import yaml


ROOT = Path(__file__).resolve().parents[2]
REQUIRED = (
    ".extensionignore",
    "extension.yml",
    "config-template.yml",
    "README.md",
    "CHANGELOG.md",
    "LICENSE",
    "skills/contract-governance/SKILL.md",
    "scripts/bash/test-smoke.sh",
    "scripts/bash/test-speckit-0162.sh",
    "scripts/python/test_contract_analyzer.py",
)
FORBIDDEN_DISTRIBUTION_FILES = (
    "contract-governance-config.yml",
    "contract-governance-warning-baseline.json",
)
REQUIRED_IGNORE_PATTERNS = {
    ".git/",
    ".github/",
    ".learnings/",
    ".DS_Store",
    "**/.DS_Store",
    "AGENTS.md",
}
EXPECTED_COMMANDS = {
    "speckit.contract-governance.init",
    "speckit.contract-governance.init-consumer",
    "speckit.contract-governance.validate-boundary",
    "speckit.contract-governance.validate-registry",
    "speckit.contract-governance.diff",
    "speckit.contract-governance.validate",
    "speckit.contract-governance.audit",
    "speckit.contract-governance.sync-map",
}
EXPECTED_HOOKS = {
    "after_plan": "speckit.contract-governance.validate-boundary",
    "before_tasks": "speckit.contract-governance.validate",
    "after_tasks": "speckit.contract-governance.validate",
}


def fail(message: str) -> None:
    print(f"distribution error: {message}", file=sys.stderr)
    raise SystemExit(1)


def main() -> None:
    missing = [name for name in REQUIRED if not (ROOT / name).is_file()]
    if missing:
        fail("missing required files: " + ", ".join(missing))

    for filename in FORBIDDEN_DISTRIBUTION_FILES:
        matches = [path for path in ROOT.rglob(filename) if ".git" not in path.parts]
        if matches:
            fail(f"project-specific file must not ship: {matches[0].relative_to(ROOT)}")

    manifest = yaml.safe_load((ROOT / "extension.yml").read_text(encoding="utf-8"))
    extension = manifest.get("extension", {})
    version = str(extension.get("version", "")).strip()
    version_file = (ROOT / "VERSION").read_text(encoding="utf-8").strip()
    if not re.fullmatch(r"\d+\.\d+\.\d+", version):
        fail(f"invalid semantic version: {version!r}")
    if version != version_file:
        fail(f"VERSION ({version_file}) differs from extension.yml ({version})")
    if extension.get("license") != "MIT":
        fail("extension.yml license must match LICENSE")
    if extension.get("category") != "process":
        fail("extension.yml category must be process")
    if extension.get("effect") != "read-write":
        fail("extension.yml effect must disclose initialization writes")
    if extension.get("repository") != "https://github.com/liyang2012/speckit-contract-governance":
        fail("extension.yml repository is missing or incorrect")

    requires = manifest.get("requires", {})
    if requires.get("speckit_version") != ">=0.16.2":
        fail("requires.speckit_version must pin the 0.16.2 compatibility floor")
    if set(requires.get("commands", [])) != {"speckit.plan", "speckit.tasks"}:
        fail("requires.commands must declare the hooked Spec Kit commands")

    commands = manifest.get("provides", {}).get("commands", [])
    if not commands:
        fail("extension.yml does not declare commands")
    command_names = {str(command.get("name", "")) for command in commands}
    if command_names != EXPECTED_COMMANDS:
        fail("extension.yml canonical command set is incomplete or unexpected")
    registered_names: set[str] = set()
    for command in commands:
        declared_names = [str(command.get("name", "")), *map(str, command.get("aliases", []))]
        duplicates = registered_names.intersection(declared_names)
        if duplicates:
            fail("duplicate command or alias: " + ", ".join(sorted(duplicates)))
        registered_names.update(declared_names)
        command_file = ROOT / str(command.get("file", ""))
        if not command_file.is_file():
            fail(f"missing command file for {command.get('name')}: {command_file}")

    hooks = manifest.get("hooks", {})
    for event, expected_command in EXPECTED_HOOKS.items():
        hook = hooks.get(event, {})
        if hook.get("command") != expected_command:
            fail(f"{event} must invoke {expected_command}")
        if hook.get("priority") != 10:
            fail(f"{event} must declare priority 10 explicitly")

    ignore_patterns = {
        line.strip()
        for line in (ROOT / ".extensionignore").read_text(encoding="utf-8").splitlines()
        if line.strip() and not line.lstrip().startswith("#")
    }
    missing_ignore = sorted(REQUIRED_IGNORE_PATTERNS - ignore_patterns)
    if missing_ignore:
        fail(".extensionignore misses source-only artifacts: " + ", ".join(missing_ignore))

    caches = [path for path in ROOT.rglob("__pycache__") if path.is_dir()]
    if caches:
        fail(f"generated cache must not ship: {caches[0].relative_to(ROOT)}")

    print(f"distribution valid: contract-governance {version}, {len(commands)} commands")


if __name__ == "__main__":
    main()
