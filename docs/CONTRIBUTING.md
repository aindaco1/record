# Contributing

Record targets macOS 15+ on Apple Silicon with Swift 6 and requires Xcode 26
or newer for development. Hosted CI and releases select Xcode 26.3 through
`scripts/ci/select-stable-xcode.sh`; the macOS 15 deployment target is unchanged.
Run the commands below from the repository root.

## Before opening a change

1. Keep screenshot, recording, transcription, clipboard, and plugin data local.
2. Put reusable domain logic in `RecordCore`; keep AppKit, ScreenCaptureKit,
   AVFoundation, and other hardware APIs behind adapters. See the
   [architecture guide](architecture.md) for module ownership.
3. Add deterministic tests for every bug fix and state transition that can be
   exercised without TCC or physical devices.
4. Document intentional security, compatibility, or data-format decisions in
   an [ADR](adr/) when they affect more than one component.
5. Avoid new dependencies when an Apple framework or a small local type is
   sufficient.

Dependency changes require an explicit review for network clients, telemetry,
process launching, file access, and implicit model downloads. Product targets
must pass `scripts/ci/check-local-only.sh`; do not weaken its patterns or add a
main-app network entitlement without a user-approved replacement for
[ADR 0002](adr/0002-local-only.md). Sparkle is a reviewed exception under
[ADR 0004](adr/0004-signed-updates-and-login.md).
[ADR 0017](adr/0017-sandboxed-parakeet-model-download.md) separately permits the
fixed-asset Parakeet XPC downloader; changes to its URL, allowed hosts, protocol,
or exact entitlement set require renewed privacy review. The
[local-only boundary](security/local-only-boundary.md) documents enforcement.

## Build and validate

```sh
swift build
swift test
./scripts/ci/validate.sh
```

The validation script runs the shared source checks and tests, verifies the
resolved dependency lock, and builds the release CLI for arm64.

Before handing off a branch, run the complete local equivalent of the hosted
CI jobs. It checks the toolchain, uses rootless Podman for pinned workflow and
shell linting, runs normal and sanitizer tests, builds arm64, assembles the
sandboxed app, and mounts both release packages:

```sh
./scripts/ci/local-gate.sh
```

Follow the [container setup guide](../containers/README.md) to install the
user-level Podman watchdog before the first local gate. Hardware capture
changes must also complete the manual capture matrix in the
[testing guide](testing.md). Never put recordings, transcripts, credentials,
signing material, or model files in fixtures or build artifacts.

To assemble, sign, install, and launch a local app for manual inspection:

```sh
./script/build_and_run.sh --verify
```

This command stops a running Record instance and replaces the development app
in the user's Applications folder. Use it when ready to test the local build.
A successful launch does not establish capture or hardware acceptance.

Release preparation and the verified CI-app handoff are documented in the
[release runbook](runbooks/release.md) and
[ADR 0012](adr/0012-verified-ci-app-reuse.md).

## Local transcription setup

Use the [Parakeet setup guide](models/parakeet.md) for the pinned developer
installer as well as in-app setup. If MacWhisper and its bundled `mw` CLI are
installed, a development checkout can provision Record's bridge explicitly:

```sh
./scripts/setup/install-macwhisper-cli.sh
```

See the [user guide](user-guide.md#macwhisper) for engine selection and
availability requirements.

## Artwork

Regenerate `Record.icns` from the canonical, reviewable SVG only when the
artwork changes:

```sh
./scripts/release/generate-icon.sh
```

## Pull requests

- Keep each PR focused and explain the failure mode or user outcome.
- Link migrated Quill/NewKap context where applicable.
- Include automated tests and identify any remaining manual verification.
- Treat compiler warnings, race reports, dropped frames, A/V drift, and failed
  state restoration as release-blocking until triaged.
- Follow the [documentation guidance](README.md#maintain-these-docs) when
  updating guides.
