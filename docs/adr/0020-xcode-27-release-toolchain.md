# ADR 0020: Require released Xcode 27 on the approved preview runner

- Status: accepted
- Date: 2026-09-21
- Amends: [ADR 0010](0010-on-device-transcript-refinement.md) and
  [ADR 0012](0012-verified-ci-app-reuse.md)

## Context

Apple released Xcode 27.0 build `27A266a`. GitHub provides that compiler on its
`xcode-27` image but still labels the runner public preview. The complete
default-engine test suite and shared validation gate have passed there, as
recorded in the [readiness report](../testing/macos-27-readiness.md). Waiting
for runner GA was a project release policy, distinct from compiler maturity.
The repository owner explicitly approved the preview runner and requested
toolchain promotion and a signed release on September 21, 2026.

## Decision

Authoritative build/package, sanitizer, CodeQL and release jobs use `xcode-27`.
The shared selector chooses `/Applications/Xcode_27.0.app/Contents/Developer`
and requires both `Xcode 27.0` and build `27A266a`. Missing or different
toolchains fail closed. The existing required **Swift tests and arm64 build**
check continues to enforce the full build job; there is no separate advisory
copy. Swift Build becomes the shared validation default. Local development
requires Xcode 27 or newer, while release automation accepts only the exact
reviewed compiler build.

CI app metadata schema v3 records and checks `xcodeVersion` and `xcodeBuild`.
Its shared validator rejects older schemas, additional or missing fields,
wrong toolchain builds and mismatched workflow/run/source identity. Release
continues to verify GitHub-hosted attestation, exact successful main-commit CI
and CodeQL, archive containment, source/executable hashes and unsigned state.
It stamps and signs the CI app without rebuilding it. All Developer ID,
notarization, entitlement, TCC identity and Sparkle signature gates remain.

The FoundationModels adviser adopts `GenerationOptions(samplingMode:)` from
the new SDK. The API supports back deployment to macOS 26, preserving the
existing availability gate and greedy sampling behavior. The application's
macOS 15 deployment target and Apple Silicon architecture do not change.

## Consequences

- Preview image outages or changes can block builds and releases. This risk
  is explicitly accepted; do not bypass a failed gate or silently substitute
  the runner's default compiler. Future compiler changes require review.
- Runner GA is no longer a prerequisite for this promotion. It must not be
  reported as having happened merely because the compiler is released.
- The released app remains the binary validated by required CI, with stricter
  compiler identity in its provenance. Release still requires actual successful
  CodeQL and public signing/notarization evidence.
- All media and metadata stay local. No network or inference entitlement is
  added. Hardware, permission and capture acceptance remains in
  [issue #6](https://github.com/aindaco1/record/issues/6).
