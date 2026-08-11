# Security Policy

## Supported versions

Security fixes target the latest released minor version. Older releases may receive
critical fixes when a safe backport is practical.

## Reporting a vulnerability

Do not open a public issue for vulnerabilities involving command execution, path
traversal, unsafe contract parsing, secret exposure, or CI bypass. Use the repository's
private security advisory channel after publication. Include affected version,
reproduction steps, impact, and any proposed mitigation.

The project does not need production credentials or network access to validate local
contract files. Reports that require real credentials should replace them with a
minimal synthetic fixture.
