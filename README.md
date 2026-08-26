# Record

Record is a local-first screen and audio recorder for macOS. It keeps Quill's
small menu-bar workflow, adds useful NewKap-inspired controls, and uses native
Swift instead of Electron.

Record 1.0 captures the main display, microphone, and system audio; keeps the
two audio sources as separate files; and can transcribe them locally. Finished
sessions are exported to a user-approved folder, with Desktop as the default.

## Requirements

- macOS 15 or newer
- Apple Silicon
- Screen & System Audio Recording and/or System Audio Recording Only access
- Microphone access when recording the microphone

## Install

[Download Record for Apple Silicon](https://github.com/aindaco1/record/releases/latest/download/Record.dmg),
open the notarized DMG, and drag **Record** onto its Applications shortcut. If
EasyDMG is already configured as the Mac's default DMG handler, opening the
same single-app image can automate that copy. No additional installer is
required. Releases are Developer ID signed, notarized, and accompanied by
SHA-256 checksums and build provenance on the
[GitHub release page](https://github.com/aindaco1/record/releases/latest).

Record has no Dock icon. Open it from the ring in the menu bar.

To uninstall, turn off **Open at Login**, quit Record, and move Record.app to
the Trash. Remove Record's container only if you also want to delete its
preferences, temporary recovery sessions, and installed transcription model.

## Use

- **Start screen recording** records the main display to a video-only
  `recording.mov` and writes `mic.caf` and `system.caf` independently.
- **Start audio-only recording** writes the same two independent audio tracks
  without capturing the display.
- **Select export folder…** changes the approved destination. Desktop is suggested on
  first use, and the sandbox grant persists across launches.
- **Open temp session** opens private recovery storage for sessions that have
  not been exported.
- **Open last recording** reveals the newest finished session from private or
  approved export storage. Record derives this from `session.json` and keeps no
  separate activity database.
- Record silently checks its signed GitHub release feed once at launch. When a
  newer version is available, Sparkle presents its standard update prompt;
  download and installation remain user approved.
- **Check for Updates…** retains the same signed flow as a manual fallback.
- **Open at Login** uses the macOS Login Items service and is off by default.

Each exported session contains an atomic `session.json` manifest. Screen
sessions also contain `recording.mov`; both recording modes retain `mic.caf`
and `system.caf`. Record validates the exported copy before deleting its
private finalized working directory. A failed export leaves the private copy
recoverable.

## Local transcription

Parakeet v3 is the default transcription engine. Record never downloads a
model itself. If the verified model is missing, Record offers a setup prompt
and **Transcript model → Set Up Parakeet Model…**. Download the pinned model
from FluidInference, then let Record verify every file and atomically import it
into local storage. See the [Parakeet setup guide](docs/models/parakeet.md).

Development checkouts can install the same pinned model directly with:

```sh
./scripts/setup/install-parakeet-model.sh
```

If MacWhisper and its bundled `mw` CLI are installed, Record provisions its
own bundled, content-checked user-script bridge. Development checkouts can
install the same bridge explicitly with:

```sh
./scripts/setup/install-macwhisper-cli.sh
```

Choose **Transcript model → MacWhisper (Small)**. This option is absent
unless MacWhisper, its bundled `mw`, and Record's sandbox helper are all
available. Record validates the MacWhisper application signature before each
invocation and never falls back silently from one engine to another.

If a local transcription fails, **Transcript model → Retry Failed
Transcription** appears until the job is retried. Record keeps both source audio
files unchanged. Voice processing reduces speaker-to-microphone echo by default;
when aligned cross-track speech still duplicates, Record conservatively removes
only high-confidence mic copies from the readable transcript and keeps the
unsuppressed result in `transcript.raw.json`. A startup recovery scan validates
interrupted media, restores playable partials, quarantines invalid partials
without deleting them, and opens only Record's temporary recovery folder from
the notification.

On macOS 26 or newer, an eligible Mac with Apple Intelligence enabled can opt
in to **Transcript model → Improve Transcript Readability**. Apple's on-device
Foundation Models framework advises Record only on bounded filled-pause and
immediate-repeat candidates; Record validates every decision, preserves timing
and source-speaker labels, and marks simultaneous cross-speaker segments as
overlapping. It never asks the model to rewrite a transcript or identify a
person. If the on-device model is unavailable or generation fails, the ordinary
local transcript still completes. A changed transcript retains the complete
pre-refinement result in `transcript.raw.json`, and
`transcript.refinement.json` records the content-free policy decisions and a
source hash.

## Built-in plugins

The Plugins menu contains small, capability-specific features rather than an
in-process arbitrary-code plugin API:

- hide notifications, the menu bar, or Desktop items from screen capture;
- rename completed sessions using sanitized templates;
- open the last completed video in an already-installed Gifski app.

These settings do not modify global macOS display preferences, download
helpers, or grant plugins network access.

## Privacy and security

Record does not upload recordings, transcripts, clipboard-derived names,
diagnostics, or identifiers. It has no accounts, analytics, cloud
transcription, or recording network client. The sandboxed main app has no
incoming or outgoing network entitlement.

The launch update check and explicit update command are the narrow exception:
Sparkle's sandboxed downloader service contacts the public GitHub release feed
and accepts only an Ed25519-signed update archive. Automatic installation and
system profiling are disabled. Enabling MacWhisper extends the local trust
boundary to the separately installed MacWhisper app.

See [Security](SECURITY.md) and the [local-only boundary](docs/security/local-only-boundary.md)
for the enforceable invariants and limitations.

See the plain-language [Privacy Policy](PRIVACY.md) for data handling.

## Development

```sh
swift build
swift test
./scripts/ci/validate.sh
./script/build_and_run.sh --verify
```

`./scripts/ci/local-gate.sh` is the complete pre-release gate. It uses rootless
Podman for pinned workflow and shell linting, runs the test and sanitizer
suites, assembles the arm64 app, audits its entitlements, and verifies the ZIP
and DMG structures.

Development requires Xcode 26 or newer. Hosted CI and releases select Xcode
26.3 explicitly; the macOS 15 deployment target remains unchanged.

For each exact `main` commit, CI retains the unsigned arm64 app that already
passed the full package gate as a short-lived, provenance-attested internal
artifact. A signed-tag release requires successful CI and CodeQL for that same
commit, verifies and stamps the app, and still performs the complete Developer
ID signing, notarization, packaging, Sparkle-signing, and readback sequence. The
handoff removes duplicate release compilation without changing the shipped app
contract; see [ADR 0012](docs/adr/0012-verified-ci-app-reuse.md).

The project uses Swift 6, AppKit, ScreenCaptureKit, AVFoundation,
VideoToolbox/AVAssetWriter, ServiceManagement, and Sparkle 2. See
[Contributing](CONTRIBUTING.md) before changing dependencies or privacy
boundaries.

## Documentation

- [Architecture](docs/architecture.md)
- [Testing](docs/testing.md)
- [Roadmap](ROADMAP.md)
- [Changelog](CHANGELOG.md)
- [Advanced configuration](docs/configuration.md)
- [Parakeet model setup](docs/models/parakeet.md)
- [Release runbook](docs/runbooks/release.md)
- [Quill migration record](docs/migration/quill-triage.md)
- [Current GitHub issue triage](docs/project/issue-triage-1.1.3.md)
- [Support](SUPPORT.md)

## Provenance and license

Record is a standalone project based on the MIT-licensed history of
[digimata/quill](https://github.com/digimata/quill). Selected NewKap behaviors
were reimplemented natively. See [third-party notices](THIRD_PARTY_NOTICES.md)
for code and artwork attribution.

Record is available under the [MIT License](LICENSE).
