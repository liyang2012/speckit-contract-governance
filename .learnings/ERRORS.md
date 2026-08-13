# Errors

Command failures and integration errors.

---

## [ERR-20260813-001] powershell-smoke-local-runtime

**Logged**: 2026-08-13T16:30:00+08:00
**Priority**: low
**Status**: pending
**Area**: tests

### Summary
The local PowerShell smoke suite could not start because PowerShell 7 is not installed.

### Error

```text
zsh: command not found: pwsh
```

### Context

- Command attempted: `pwsh -File scripts/powershell/test-smoke.ps1`.
- The repository still runs the PowerShell suite on `windows-latest` in GitHub Actions.
- Bash, Python, distribution, Skill, and Spec Kit 0.16.2 installation checks passed locally.

### Suggested Fix

Use the Windows CI job as the PowerShell verification layer, or install PowerShell 7 locally before requiring a local cross-platform run.

### Metadata

- Reproducible: yes
- Related Files: scripts/powershell/test-smoke.ps1, .github/workflows/ci.yml
- Pattern-Key: shell.command-not-found
- Recurrence-Count: 1
- First-Seen: 2026-08-13
- Last-Seen: 2026-08-13

---

## [ERR-20260813-002] unsafe-temporary-cleanup-command

**Logged**: 2026-08-13T16:35:00+08:00
**Priority**: low
**Status**: resolved
**Area**: tests

### Summary
A combined CI-install simulation was rejected because it ended with recursive removal commands.

### Error

```text
rm -f style commands are not permitted
```

### Context

- The rejected command had not started, so it did not modify the repository or create the proposed temporary directories.
- The actual goal was only to verify the pinned official Spec Kit source.

### Suggested Fix

Use `uv tool run --from <source> specify --version` when only package resolution and version need verification.

### Metadata

- Reproducible: yes
- Related Files: .github/workflows/ci.yml
- Pattern-Key: shell.nonzero-exit
- Recurrence-Count: 1
- First-Seen: 2026-08-13
- Last-Seen: 2026-08-13

### Resolution

- **Resolved**: 2026-08-13T16:36:00+08:00
- **Notes**: Verified the pinned Git source with a side-effect-minimized `uv tool run`; it reported `specify 0.16.2`.

---

## [ERR-20260811-002] github-publish-prerequisite

**Logged**: 2026-08-11T14:35:22+08:00
**Priority**: medium
**Status**: resolved
**Area**: infra

### Summary

GitHub publishing could not start because the required GitHub CLI was not installed.

### Error

```text
zsh: command not found: gh
```

### Context

- The requested remote was reachable and returned no refs, consistent with an empty repository.
- The publish workflow requires `gh` to be installed and authenticated before initializing, committing, and pushing.

### Suggested Fix

Install GitHub CLI, run `gh auth login`, verify with `gh auth status`, and retry the publish workflow.

### Metadata

- Reproducible: yes
- Related Files: none
- Pattern-Key: infra.github-cli-missing
- Recurrence-Count: 1
- First-Seen: 2026-08-11
- Last-Seen: 2026-08-11

### Resolution

- **Resolved**: 2026-08-11T14:42:04+08:00
- **Notes**: Installed GitHub CLI and verified the authenticated `liyang2012` account.

---

## [ERR-20260811-003] github-push-ssl

**Logged**: 2026-08-11T14:42:04+08:00
**Priority**: low
**Status**: resolved
**Area**: infra

### Summary

The first Git push attempt failed during the TLS connection to GitHub.

### Error

```text
LibreSSL SSL_connect: SSL_ERROR_SYSCALL in connection to github.com:443
```

### Context

- Authentication had already succeeded.
- A subsequent GitHub API request and `git ls-remote` both succeeded, confirming a transient connection failure.

### Suggested Fix

Recheck API and Git remote connectivity, then retry the unchanged push.

### Metadata

- Reproducible: no
- Related Files: none
- Pattern-Key: infra.github-transient-ssl
- Recurrence-Count: 1
- First-Seen: 2026-08-11
- Last-Seen: 2026-08-11

### Resolution

- **Resolved**: 2026-08-11T14:42:04+08:00
- **Notes**: Connectivity checks succeeded immediately after the failed push.

---

## [ERR-20260811-004] github-https-write-denied

**Logged**: 2026-08-11T14:43:44+08:00
**Priority**: medium
**Status**: resolved
**Area**: infra

### Summary

GitHub rejected HTTPS pushes even though the authenticated account had repository admin permission.

### Error

```text
remote: Permission to liyang2012/speckit-contract-governance.git denied to liyang2012.
fatal: The requested URL returned error: 403
```

### Context

- The GitHub API reported `push: true` and `admin: true` for the account.
- Configuring Git to use the GitHub CLI credential helper produced the same result, indicating the HTTPS token lacked repository contents write permission.
- SSH authentication succeeded for the same GitHub account.

### Suggested Fix

Use the authenticated SSH remote, or refresh the HTTPS token with repository contents write permission.

### Metadata

- Reproducible: yes
- Related Files: none
- Pattern-Key: infra.github-https-token-write-denied
- Recurrence-Count: 1
- First-Seen: 2026-08-11
- Last-Seen: 2026-08-11

### Resolution

- **Resolved**: 2026-08-11T14:43:44+08:00
- **Notes**: Verified the existing SSH key for `liyang2012` and switched this repository remote to SSH.

---

## [ERR-20260811-005] initial-github-actions-smoke

**Logged**: 2026-08-11T14:47:50+08:00
**Priority**: high
**Status**: resolved
**Area**: tests

### Summary

The first GitHub Actions run failed in both Bash and PowerShell smoke suites despite passing locally before repository initialization.

### Error

```text
Bash smoke suite: Process completed with exit code 128 during the no-change contract diff setup.
PowerShell smoke suite: command help and initialization assertions returned exit code 1.
```

### Context

- Bash smoke fixtures create commits without setting a fixture-local Git identity; hosted runners do not provide the developer's global identity.
- The PowerShell smoke helper declares an `Args` parameter, colliding case-insensitively with PowerShell's automatic `$args` variable, and invokes scripts through a nested command string.
- The PowerShell harness captures but does not print the underlying child-script error on assertion failure, obscuring the first failure boundary.
- After argument reporting was fixed, Windows exposed a second boundary: `Find-RepoRoot` traversed past a drive root into an empty parent path and passed it to `Join-Path`.
- After root traversal was fixed, Windows exposed invalid `return if` syntax in `diff-contract.ps1` and terminating `Write-Error` calls that hid detailed validation failures under `ErrorActionPreference=Stop`.
- After those fixes, Windows exposed CP1252 failures when Python emitted Chinese TSV text and array splatting that treated `-BootstrapOk` as a positional service value.

### Suggested Fix

Set test-local Git identity for temporary repositories. Refactor the PowerShell capture helper to use a non-reserved argument name and direct argument-array invocation, include captured output on failure, then rerun both smoke jobs.

### Metadata

- Reproducible: yes
- Related Files: scripts/bash/test-smoke.sh, scripts/powershell/test-smoke.ps1, scripts/powershell/common-utils.ps1, .github/workflows/ci.yml
- Pattern-Key: tests.ci-clean-runner-assumptions
- Recurrence-Count: 4
- First-Seen: 2026-08-11
- Last-Seen: 2026-08-11

### Resolution

- **Resolved**: 2026-08-11T15:03:35+08:00
- **Commit/PR**: a6fd448
- **Notes**: Added fixture-local Git identity, fixed PowerShell argument capture and drive-root traversal, repaired PowerShell control flow and failure reporting, forced UTF-8 for Python subprocesses, and used hashtable splatting for script-to-script named parameters. GitHub Actions run 31467384088 passed both jobs.

---

## [ERR-20260811-001] minimal-example-validation

**Logged**: 2026-08-11T00:00:00+08:00
**Priority**: medium
**Status**: resolved
**Area**: docs

### Summary
The first standalone minimal example did not satisfy its own boundary and required-field rules.

### Error

```text
plan did not contain a recognized no-cross-service-database boundary
resolved required fields data.records[].id and data.records[].name were not found
```

### Context

- The example used an English boundary sentence while the current shell validator recognizes Chinese policy phrases.
- Array traversal is automatic in `schema_has_path`; dotted required-field paths must not include `[]`.

### Suggested Fix

Use a recognized boundary sentence, change array paths to `data.records.id` and
`data.records.name`, document the syntax, and rerun example validation.

### Metadata

- Reproducible: yes
- Related Files: examples/minimal/specs/001-catalog/plan.md, examples/minimal/contracts/_consumers/web-app.yaml
- Pattern-Key: docs.example-must-pass-governance
- Recurrence-Count: 1
- First-Seen: 2026-08-11
- Last-Seen: 2026-08-11

### Resolution

- **Resolved**: 2026-08-11T00:00:00+08:00
- **Notes**: Corrected the example paths and boundary wording, documented implicit array traversal, and verified zero structural or semantic findings.

---
