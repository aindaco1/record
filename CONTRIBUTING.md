# Contributing

Record currently targets macOS 15+ on Apple Silicon with Swift 6.

## Before opening a change

1. Keep recording, transcription, and plugin data local.
2. Put reusable domain logic in `RecordCore`; keep AppKit, ScreenCaptureKit,
   AVFoundation, and other hardware APIs behind adapters.
3. Add deterministic tests for every bug fix and state transition that can be
   exercised without TCC or physical devices.
4. Document intentional security, compatibility, or data-format decisions in
   an ADR when they affect more than one component.
5. Avoid new dependencies when an Apple framework or a small local type is
   sufficient.

Dependency changes require an explicit review for network clients, telemetry,
process launching, file access, and implicit model downloads. Product targets
must pass `scripts/ci/check-local-only.sh`; do not weaken its patterns or add a
network entitlement without a user-approved replacement for ADR 0002.

Run the fast source and test gate:

```sh
./scripts/ci/validate.sh
```

Before handing off a branch, run the complete local equivalent of the hosted
CI jobs. It checks the toolchain, uses rootless Podman for pinned workflow and
shell linting, runs tests, builds arm64, assembles the sandboxed app, and mounts
both release packages:

```sh
./scripts/ci/local-gate.sh
```

Hardware capture changes must also complete the manual capture matrix in
`docs/testing.md`. Never put recordings, transcripts, credentials, signing
material, or model files in fixtures or build artifacts.

## Pull requests

- Keep each PR focused and explain the failure mode or user outcome.
- Link migrated Quill/NewKap context where applicable.
- Include automated tests and identify any remaining manual verification.
- Treat compiler warnings, race reports, dropped frames, A/V drift, and failed
  state restoration as release-blocking until triaged.
