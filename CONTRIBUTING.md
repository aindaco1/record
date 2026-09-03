# Contributing

Record currently targets macOS 15+ on Apple Silicon with Swift 6 and requires
Xcode 26 or newer for development. Authoritative hosted builds select the
pinned stable Xcode with `scripts/ci/select-stable-xcode.sh`.

## Before opening a change

1. Keep screenshot, recording, transcription, clipboard, and plugin data local.
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
main-app network entitlement without a user-approved replacement for ADR 0002.
Sparkle is a reviewed exception under ADR 0004. ADR 0017 separately permits the
fixed-asset Parakeet XPC downloader; changes to its URL, allowed hosts, protocol,
or exact entitlement set require renewed privacy review.

Run the fast source and test gate:

```sh
./scripts/ci/validate.sh
```

Before handing off a branch, run the complete local equivalent of the hosted
CI jobs. It checks the toolchain, uses rootless Podman for pinned workflow and
shell linting, runs normal and sanitizer tests, builds arm64, assembles the
sandboxed app, and mounts both release packages:

```sh
./scripts/ci/local-gate.sh
```

On macOS, install the user-level Podman watchdog once before running the local
gate:

```sh
./scripts/setup/install-podman-watchdog.sh
```

The watchdog starts the existing Podman machine at login and checks it every
five minutes. It deliberately runs through launchd with an abandoned process
group so the VM and `gvproxy` survive the one-shot start command. The local
gate and watchdog use the active `podman` on `PATH`, then the Homebrew and
package-installer locations as fallbacks, so one installation owns both the VM
and its helper processes. Set `RECORD_PODMAN_CLI` to an absolute executable
path only when an explicit override is required. Recovery never resets
machines or prunes images, containers, or volumes.

The installer defaults to `podman-machine-default` with Libkrun. To dedicate a
separate AppleHV machine to the gate, initialize it first, then install the
watchdog with matching settings:

```sh
CONTAINERS_MACHINE_PROVIDER=applehv podman machine init record-release-gate
RECORD_PODMAN_MACHINE_NAME=record-release-gate \
  RECORD_PODMAN_MACHINE_PROVIDER=applehv \
  ./scripts/setup/install-podman-watchdog.sh
podman system connection default record-release-gate
```

Hardware capture changes must also complete the manual capture matrix in
`docs/testing.md`. Never put recordings, transcripts, credentials, signing
material, or model files in fixtures or build artifacts.

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
