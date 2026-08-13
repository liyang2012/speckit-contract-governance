# Releasing

1. Decide the next semantic version from the compatibility impact.
2. Update `VERSION` and `extension.version` in `extension.yml`.
3. Move user-visible entries from `Unreleased` into a dated changelog section.
4. Run Bash syntax checks, Bash smoke tests, Python unit tests, distribution validation,
   the pinned Spec Kit 0.16.2 installation smoke test, and PowerShell smoke tests.
5. Install the local directory into a clean Spec Kit 0.16.2 fixture and run one
   initialization, validation, audit, diff preview, and SERVICE-MAP preview.
6. Review the distribution for internal names, credentials, absolute paths, generated
   caches, and customer fixtures.
7. Tag the release only after all checks pass.

Release archives should contain the extension manifest, commands, scripts, config
template, Skill source, documentation, license, and changelog. They should not contain
an installed project configuration or warning baseline.

Run the pinned compatibility smoke test with:

```bash
bash scripts/bash/test-speckit-0162.sh
```
