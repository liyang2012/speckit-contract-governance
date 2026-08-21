# Minimal example

This fixture demonstrates the ownership split between one Provider and one frontend
Consumer. Copy the extension into `.specify/extensions/contract-governance/` in a
temporary project, then use the files here as the project's `contracts/` and `specs/`
trees.

The example intentionally keeps `SERVICE-MAP.md` as a derived view. Edit the Provider
OpenAPI or Consumer expectation first, then preview topology synchronization.

For an existing Provider semantic edit, run `diff-contract --service catalog-service
--write`; the generated `x-changelog` is written into the Provider file and then checked
with `check-changelog`. Set `changelog_baseline_ref` to the full commit accepted as the
start of incremental governance. The initial Provider document itself is exempt.
