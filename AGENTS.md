# Contributor Context

Read `docs/contract-model.md` before changing validation semantics.

Keep Provider contracts, backend Consumer registries, frontend Consumer contracts,
and derived SERVICE-MAP data as separate ownership layers. Do not add project-specific
services, credentials, endpoints, warning baselines, or business rules to this repository.

Every behavior change requires a focused analyzer test and, when it affects a shell
entrypoint, a smoke test. Keep Bash compatible with macOS Bash 3.x and preserve
PowerShell parity for user-facing commands.

Documentation fixtures must pass the shipped validators. In `required_fields`, use
dotted paths such as `data.records.id`; array traversal is implicit and does not use `[]`.
