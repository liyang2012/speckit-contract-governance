# Contributing

Thank you for improving Spec Kit Contract Governance.

## Scope

Changes belong here when they improve the reusable governance model, installer
metadata, commands, validators, reports, examples, or documentation. Project-specific
service names, credentials, internal URLs, real business contracts, and warning
baselines belong in the consuming project.

## Compatibility rules

1. Provider truth remains in `contracts/<service>/api.yaml` and owned event schemas.
2. Backend caller truth remains in the Consumer service registry `consumes` section.
3. Frontend expectations remain in `_consumers`; they never define Provider operations.
4. `SERVICE-MAP.md` remains derived and reproducible.
5. Read-only commands stay read-only unless the user explicitly supplies `--write`.
6. `PENDING` is never promoted automatically from structural evidence alone.
7. New validation rules use stable machine-readable codes and include migration guidance.

## Development setup

Required tools:

- Bash
- Python 3
- PyYAML
- PowerShell 7 for PowerShell parity checks

Run the complete local suite:

```bash
bash -n scripts/bash/*.sh
bash scripts/bash/test-smoke.sh
PYTHONDONTWRITEBYTECODE=1 python3 scripts/python/test_contract_analyzer.py -v
PYTHONDONTWRITEBYTECODE=1 python3 scripts/python/validate_distribution.py
pwsh -File scripts/powershell/test-smoke.ps1
```

## Change expectations

- Bug fix: add a regression test that fails before the fix.
- New rule: document severity, stable code, configuration, false-positive boundary,
  and remediation.
- Schema change: describe compatibility impact and update examples.
- Bash behavior change: keep the PowerShell command behavior aligned.
- Release: update `VERSION`, `extension.yml`, and `CHANGELOG.md` together.

## Pull requests

Keep each pull request focused. State the contract invariant being changed, include
test evidence, and call out any intentionally unsupported migration. Do not include
customer data or copied production contracts in fixtures.
