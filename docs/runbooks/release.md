# Release runbook

Record releases are Apple-Silicon-only, Developer ID signed, notarized, and
published from a signed semantic-version tag.

## Credentials

The existing Apple Auth directory can remain the offline source of the
Developer ID PKCS#12 file and App Store Connect API key. Never copy that
directory into this repository. GitHub stores only base64-encoded credential
contents and passwords as protected `release` environment secrets. The Sparkle
Ed25519 private key also remains outside the repository and is stored only as
the protected `SPARKLE_ED25519_PRIVATE_KEY` environment secret.

Before release, verify locally that the certificate is not expired, the API key
still belongs to the expected issuer, and the files are readable only by the
account performing the release. Rotate the GitHub secrets whenever those source
files change. Temporary runner copies use a restrictive umask and exact-path
cleanup; the temporary keychain is deleted even after failure.

## Candidate preparation

1. Run `./scripts/ci/local-gate.sh` on the exact candidate commit.
2. Complete the implemented 1.0 manual smoke cases in `docs/testing.md`; mark
   future source-picker, camera, pause/resume, and editor rows not applicable.
3. Add `docs/releases/MAJOR.MINOR.PATCH.md` and finalize `CHANGELOG.md`.
4. Merge the candidate to `main` and wait for all hosted checks.
5. Create and push a signed annotated `vMAJOR.MINOR.PATCH` tag on that exact
   `main` commit.
6. Approve the protected `release` environment after confirming the candidate
   commit and tag.

The active `Protect release tags` repository ruleset allows new `v*` tags but
blocks updates and deletion. If a version is tagged incorrectly, publish a new
version after fixing the candidate; do not reuse or move the released tag.
SSH tag verification is pinned to `.github/allowed_signers`; changing that
trust root requires the same security review as changing release credentials.

The release workflow revalidates the tag and source, requires the tag to identify
the checked-out commit, builds arm64, signs Sparkle's nested helpers inside-out
and then Record with hardened runtime and audited entitlements. It rejects any
change to the bundle identifier, Apple signing team, or Developer ID designated
requirement recorded in `Configuration/TCCIdentity.plist`, notarizes and staples
the app and DMG, and publishes provenance. It generates `appcast.xml`
from the final notarized ZIP and signs both the update archive and feed with the
protected Sparkle key.

`SHA256SUMS` covers the ZIP, DMG, signed appcast, resolved dependency lock, and
build metadata.
`BUILD-METADATA.txt` records the source commit/tree, commit timestamp, app/build
versions, deployment target, architecture, Swift, and Xcode without local paths.

## Post-release verification

1. Verify the GitHub artifact attestation.
2. Run `shasum -a 256 -c SHA256SUMS` beside all downloaded artifacts.
3. Validate the stapled DMG with `xcrun stapler validate` and Gatekeeper with
   `spctl --assess --type open --context context:primary-signature`.
4. Install on a clean macOS 15+ Apple Silicon account and verify the first-run
   permission flow, local-only boundary, recording, recovery, and uninstall.
5. Install the previous release, choose **Check for Updates…**, and verify the
   signed feed downloads, replaces, and relaunches the new notarized version.
6. Confirm the previous version's microphone, screen/system-audio, and
   system-audio-only grants remain enabled and neither recording path repeats
   an approved prompt. Compare both apps with `scripts/ci/check-tcc-identity.sh`.
