#!/usr/bin/env python3
"""Validate the standalone extension distribution before release."""

from __future__ import annotations

import re
import sys
from pathlib import Path

import yaml


ROOT = Path(__file__).resolve().parents[2]
REQUIRED = (
    "extension.yml",
    "config-template.yml",
    "README.md",
    "CHANGELOG.md",
    "LICENSE",
    "skills/contract-governance/SKILL.md",
    "scripts/bash/test-smoke.sh",
    "scripts/python/test_contract_analyzer.py",
)
FORBIDDEN_DISTRIBUTION_FILES = (
    "contract-governance-config.yml",
    "contract-governance-warning-baseline.json",
)


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

    commands = manifest.get("provides", {}).get("commands", [])
    if not commands:
        fail("extension.yml does not declare commands")
    for command in commands:
        command_file = ROOT / str(command.get("file", ""))
        if not command_file.is_file():
            fail(f"missing command file for {command.get('name')}: {command_file}")

    caches = [path for path in ROOT.rglob("__pycache__") if path.is_dir()]
    if caches:
        fail(f"generated cache must not ship: {caches[0].relative_to(ROOT)}")

    print(f"distribution valid: contract-governance {version}, {len(commands)} commands")


if __name__ == "__main__":
    main()
