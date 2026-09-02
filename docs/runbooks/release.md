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
2. Complete every implemented manual smoke case in `docs/testing.md`; mark only
   explicitly future camera, editor, 60-fps, and extension-host rows not
   applicable.
3. Add `docs/releases/MAJOR.MINOR.PATCH.md` and finalize `CHANGELOG.md`.
4. Merge the candidate to `main` and wait for all hosted checks.
5. Within seven days of the successful `main` CI run, create and push a signed
   annotated `vMAJOR.MINOR.PATCH` tag on that exact commit.
6. Approve the protected `release` environment after confirming the candidate
   commit and tag.

The active `Protect release tags` repository ruleset allows new `v*` tags but
blocks updates and deletion. If a version is tagged incorrectly, publish a new
version after fixing the candidate; do not reuse or move the released tag.
SSH tag verification is pinned to `.github/allowed_signers`; changing that
trust root requires the same security review as changing release credentials.

The release workflow revalidates the tag and fast shared source contract and
requires successful `CI` and `CodeQL` push runs for that exact `main` commit. It
verifies GitHub-hosted provenance and bounded extraction for the CI-assembled,
package-tested unsigned arm64 app, matches its executable, dependency lock,
Xcode 26.3 version, source plist, and release-script hashes, then stamps only the
release version and build number. This is the same plist operation used by a
fresh local assembly; the app code is the exact production binary already
exercised by CI. See ADR 0012.

The CI app handoff deliberately excludes release-only package tools. Before
signed-feed generation, the release restores Sparkle's `generate_appcast`
binary from the locked Swift package graph, rejects any `Package.resolved`
change, and does not compile or replace the attested app.

Release then signs Sparkle's nested helpers inside-out and Record with hardened
runtime and audited entitlements. It rejects any change to the bundle
identifier, Apple signing team, or Developer ID designated requirement recorded
in `Configuration/TCCIdentity.plist`, notarizes and staples the app and DMG, and
publishes provenance. The DMG contains exactly one real `Record.app` plus an
`Applications` symbolic link to `/Applications`. After notarization,
`scripts/release/verify-dmg.sh` mounts the final image read-only and rechecks
that shared layout contract, bundle structure, signatures, entitlements, stable
TCC identity, stapled tickets, and Gatekeeper acceptance. Only then does the
workflow generate `appcast.xml` from the final notarized ZIP and sign both the
update archive and feed with the protected Sparkle key.

`SHA256SUMS` covers the ZIP, DMG, signed appcast, resolved dependency lock, and
build metadata.
`BUILD-METADATA.txt` records the source commit/tree, commit timestamp, app/build
versions, deployment target, architecture, Swift, and Xcode without local paths.

## Post-release verification

1. Download the public release assets, not short-lived workflow artifacts.
   Verify GitHub artifact attestations for `Record.zip`, `Record.dmg`, and
   `appcast.xml`; the checksum manifest and metadata are covered by
   `SHA256SUMS`, not separate attestations.
2. Run `shasum -a 256 -c SHA256SUMS` beside all downloaded artifacts.
3. Run `scripts/release/verify-dmg.sh` on the absolute path to the downloaded
   `Record.dmg`. It verifies image integrity, the exact app-plus-Applications
   layout, app and DMG signatures, entitlements, TCC identity, stapled tickets,
   and Gatekeeper acceptance.
4. Install on a clean macOS 15+ Apple Silicon account and verify the first-run
   permission flow, local-only boundary, recording, recovery, and uninstall.
5. Install and launch the previous release, verify its automatic signed-feed
   prompt downloads, replaces, and relaunches the new notarized version, then
   exercise **Check for Updates…** separately as the manual fallback.
6. Confirm the previous version's microphone, screen/system-audio, and
   system-audio-only grants remain enabled and neither recording path repeats
   an approved prompt. Compare both apps with `scripts/ci/check-tcc-identity.sh`.
7. After every public and updater check passes, delete the merged release
   branch and short-lived CI app artifacts. Keep signed tags, GitHub release
   assets, the current installed app, and only the dependency caches and test
   builds still needed for development.
