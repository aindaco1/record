# ADR 0012: Reuse the verified exact-commit CI app for releases

- Status: accepted
- Date: 2026-08-26

## Context

Record's signed-tag workflow repeated the same dependency resolution, Swift
tests, and release compilation that had already passed in CI for the tagged
`main` commit. In the 1.2.1 release, source validation occupied 3 minutes 30
seconds of the 5 minute 12 second active release job. The following app-build
step took only 13 seconds because validation had already populated SwiftPM's
release build tree. A separate cold local release build took 1 minute 59
seconds, so simply deleting validation would move much of the work rather than
remove it.

The release still needs an app whose code and dependencies are exactly those
reviewed by CI, and it must not weaken signing, notarization, packaging, update
signatures, stable TCC identity, or downloaded-artifact verification.

## Decision

The authoritative stable-Xcode CI job assembles and package-tests one unsigned
arm64 `Record.app` for each exact `main` commit. After those checks pass, CI
places that app in a bounded internal archive, records the commit, workflow run,
Xcode version, executable hash, dependency-lock hash, and release-script hashes,
issues GitHub-hosted build provenance for the archive, and retains it for seven
days. The archive is an internal handoff and is never a release asset.

A signed-tag release requires successful `CI` and `CodeQL` push runs for the
same commit on `main`. It downloads the artifact named for that commit and
verifies the attestation signer workflow, source ref and digest, GitHub-hosted
runner policy, run identity, bounded traversal-safe archive layout, internal
symbolic-link containment, metadata schema, Xcode version, executable hash,
dependency lock, source plist, assembly/stamping scripts, package contract, and
unsigned state.

Release changes only `CFBundleShortVersionString` and `CFBundleVersion` in the
restored app's external `Info.plist`, which is the same stamping operation used
by a fresh local assembly. It then runs the existing inside-out Developer ID
signing, entitlement and TCC-identity checks, app and DMG notarization and
stapling, ZIP/DMG generation and readback, Sparkle signing, checksums,
attestation, and publication steps without alteration.

The release also reruns the shared fast source contract and rejects a dirty
checkout. Full Swift tests, the arm64 release build, sanitizer suites, package
rehearsal, and Xcode compatibility coverage remain in CI and the local release
gate; they are accepted by release only from the exact successful commit.

## Consequences

- The released executable is the same exact-commit production binary already
  exercised by CI rather than a second compilation of the same source.
- A release fails closed if its exact CI/CodeQL evidence, attestation, artifact,
  metadata, source hashes, or package contract is missing or inconsistent.
- Tags should be created within seven days of the successful `main` CI run.
- The fixed time for two Apple notarization submissions, signing, packaging,
  readback, and publication remains. Hosted improvement must be measured from
  the first successful tag run rather than inferred from the local projection.
- No product data, recording content, transcript, model, credential, signing
  material, or network entitlement enters the CI handoff.
