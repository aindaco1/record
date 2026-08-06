# Release runbook

Record releases are Apple-Silicon-only, Developer ID signed, notarized, and
published from a signed semantic-version tag.

## Credentials

The existing Apple Auth directory can remain the offline source of the
Developer ID PKCS#12 file and App Store Connect API key. Never copy that
directory into this repository. GitHub stores only base64-encoded credential
contents and passwords as protected `release` environment secrets.

Before release, verify locally that the certificate is not expired, the API key
still belongs to the expected issuer, and the files are readable only by the
account performing the release. Rotate the GitHub secrets whenever those source
files change. Temporary runner copies use a restrictive umask and exact-path
cleanup; the temporary keychain is deleted even after failure.

## Candidate preparation

1. Run `./scripts/ci/local-gate.sh` on the exact candidate commit.
2. Complete the hardware matrix in `docs/testing.md`.
3. Create and push a signed annotated `vMAJOR.MINOR.PATCH` tag.
4. Approve the protected `release` environment only after hosted checks pass.

The active `Protect release tags` repository ruleset allows new `v*` tags but
blocks updates and deletion. If a version is tagged incorrectly, publish a new
version after fixing the candidate; do not reuse or move the released tag.

The release workflow revalidates the tag and source, requires the tag to identify
the checked-out commit, builds arm64, signs with hardened runtime and the audited
entitlements, notarizes/staples both app and DMG, and publishes provenance.

`SHA256SUMS` covers the ZIP, DMG, resolved dependency lock, and build metadata.
`BUILD-METADATA.txt` records the source commit/tree, commit timestamp, app/build
versions, deployment target, architecture, Swift, and Xcode without local paths.

## Post-release verification

1. Verify the GitHub artifact attestation.
2. Run `shasum -a 256 -c SHA256SUMS` beside all downloaded artifacts.
3. Validate the stapled DMG with `xcrun stapler validate` and Gatekeeper with
   `spctl --assess --type open --context context:primary-signature`.
4. Install on a clean macOS 15+ Apple Silicon account and verify the first-run
   permission flow, local-only boundary, recording, recovery, and uninstall.
