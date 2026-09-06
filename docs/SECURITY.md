# Security policy

## Supported versions

| Version | Security updates |
|---|---|
| 1.4.x | Yes |
| 1.3.x and earlier | No |

Use the latest release in the supported series. See the
[changelog](../CHANGELOG.md) for versioned changes.

## Reporting a vulnerability

Please use [GitHub's private vulnerability reporting](https://github.com/aindaco1/record/security/advisories/new)
for this repository. Do not open a public issue for vulnerabilities involving
privacy boundaries, arbitrary code execution, permissions, signing, plugins,
or recording data.

Describe the affected version and reproduction steps using synthetic examples.
Do not attach captured content, transcripts, clipboard contents, credentials,
or security-scoped bookmark data. For ordinary questions and bugs, follow the
[support guide](SUPPORT.md).

## Security design

The [local-only boundary](security/local-only-boundary.md) is the reference for
security invariants, enforcement mechanisms, reviewed helper exceptions, and
verification commands. The [privacy policy](PRIVACY.md) explains data handling
and retention for users. The [release runbook](runbooks/release.md) describes
signing, notarization, update integrity, and public-asset verification.
