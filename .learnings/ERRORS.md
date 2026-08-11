# Errors

Command failures and integration errors.

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
