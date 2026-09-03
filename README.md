# Record

Record is a local-first screen and audio recorder for macOS. It keeps Quill's
small menu-bar workflow, adds useful NewKap-inspired controls, and uses native
Swift instead of Electron.

Record captures screenshots, screen video, microphone audio, and system audio;
keeps the two recording audio sources as separate files; and can transcribe
them locally. Finished media is exported to a user-approved folder, with
Desktop as the default.

## Requirements

- macOS 15 or newer
- Apple Silicon
- Screen Recording access for full-display/area screenshots and screen video;
  Apple's window/application picker can grant selection-scoped screenshot access
- Screen & System Audio Recording and/or System Audio Recording Only access for
  recording system audio
- Microphone access when recording the microphone

## Install

[Download Record for Apple Silicon](https://github.com/aindaco1/record/releases/latest/download/Record.dmg),
open the notarized DMG, and drag **Record** onto its Applications shortcut. If
EasyDMG is already configured as the Mac's default DMG handler, opening the
same single-app image can automate that copy. No additional installer is
required. Releases are Developer ID signed, notarized, and accompanied by
SHA-256 checksums and build provenance on the
[GitHub release page](https://github.com/aindaco1/record/releases/latest).

The current release is [Record 1.3.2](https://github.com/aindaco1/record/releases/tag/v1.3.2),
build 16, published September 2, 2026.

Record has no Dock icon. Open it from the ring in the menu bar.

To uninstall, turn off **Settings… → General → Open Record at Login**, quit
Record, and move Record.app to the Trash. Remove Record's container only if you
also want to delete its preferences, temporary recovery sessions, and installed
transcription model.

## Use

- **Capture Full Display** (Command-Shift-1) captures the display containing
  the pointer.
- **Capture Window or Application…** (Command-Shift-2) opens Apple's selector.
  A window captures that window; an application captures its visible windows.
  This selection-scoped path does not request broad Screen Recording access.
- **Capture Area…** (Command-Shift-4) reuses Record's display-local drag
  overlay. Full-display and area capture request Screen Recording access on
  first use. Screenshots can include Record's own windows, exclude the cursor,
  and run during a recording; the area overlay is removed before capture.
- Screenshots save immediately to the approved export folder and independently
  copy a lossless PNG to the clipboard. Disk files default to native-resolution
  lossless PNG; **Settings… → Screenshots** can select 95%-quality JPEG, adjust
  quality and sound, edit a shortcut, or turn one Off. JPEG transparency is
  flattened onto white.

- **Start screen recording** records the main display to a video-only
  `recording.mov` and writes `mic.wav` and `system.wav` independently as
  uncompressed 24-bit PCM.
- **Start audio-only recording** writes the same two independent audio tracks
  without capturing the display.
- **Settings… → General → Save to** changes the one approved destination for
  screenshots and completed screen or audio recordings. Desktop is suggested
  on first use and the sandbox grant persists across launches.
- **Open Recovery Folder…** appears only while private failed, interrupted, or
  unexported session material needs inspection.
- **Open last recording** reveals the newest finished session from private or
  approved export storage. Record derives this from `session.json` and keeps no
  separate activity database.
- Record silently checks its signed GitHub release feed once at launch. When a
  newer version is available, Sparkle presents its standard update prompt;
  download and installation remain user approved.
- **Check for Updates…** retains the same signed flow as a manual fallback.
- **Settings… → General → Open Record at Login** uses the macOS Login Items
  service and is off by default.

Each exported session contains an atomic `session.json` manifest. Screen
sessions also contain `recording.mov`; both recording modes contain `mic.wav`
and `system.wav`. Record keeps its AAC/CAF capture sources in private recovery
storage until it has validated the complete exported session, then removes the
private working directory. A failed conversion or export leaves those private
sources recoverable.

Record accepts only real, non-symlink local media files at recovery, inspection,
export, recent-video, and Gifski handoff boundaries. Session filenames and
speaker defaults come from one shared local contract rather than separate UI,
capture, and transcription copies.

## Local transcription

Parakeet v3 is the default transcription engine. If the verified model is
missing, open **Settings… → Recording → Set Up Parakeet Model…** and choose
**Download and Install**. A dedicated sandboxed helper downloads only Record's
pinned GitHub release asset; Record independently verifies the archive and
every FluidInference model file before atomic local installation. Manual import
remains available. See the [Parakeet setup guide](docs/models/parakeet.md).

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

Open **Settings… → Recording** and choose **MacWhisper (Small)** from **Model**.
This option is absent unless MacWhisper, its bundled `mw`, and Record's sandbox
helper are all available. Record validates the MacWhisper application signature
before each invocation and never falls back silently from one engine to another.

If a local transcription fails, **Retry Failed Transcription** appears in the
Record menu until the job is retried. Record keeps both source audio
files unchanged. Voice processing reduces speaker-to-microphone echo by default;
when aligned cross-track speech still duplicates, Record conservatively removes
only high-confidence mic copies from the readable transcript and keeps the
unsuppressed result in `transcript.raw.json`. A startup recovery scan validates
interrupted media, restores playable partials, quarantines invalid partials
without deleting them, and opens only Record's temporary recovery folder from
the notification.

On macOS 26 or newer, an eligible Mac with Apple Intelligence enabled can opt
in to **Settings… → Recording → Improve Transcript Readability**. Apple's on-device
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

Settings groups small, capability-specific features by what they affect rather
than presenting an in-process arbitrary-code plugin API:

- hide notifications, the menu bar, or Desktop items from screen capture;
- rename completed sessions using sanitized templates;
- hand the last completed video to an already-installed Gifski app from the
  Record menu.

These settings do not modify global macOS display preferences, download
helpers, or grant plugins network access.

## Privacy and security

Record does not upload screenshots, recordings, transcripts, clipboard
content or clipboard-derived names, diagnostics, or identifiers. It has no
accounts, analytics, cloud transcription, or capture network client. The
sandboxed main app has no incoming or outgoing network entitlement.

Network access is confined to sandboxed services. Sparkle's downloader contacts
the signed GitHub update feed. Only after **Download and Install** is selected,
the separate model helper fetches the fixed Parakeet asset; it receives no URL,
recording data, transcript, identifier, diagnostic, or general file-system
access. The main process retains no incoming or outgoing network entitlement.
Enabling MacWhisper extends the local trust boundary to the separately installed
MacWhisper app.

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
- [Record 1.3.2 release notes](docs/releases/1.3.2.md)
- [Quill migration record](docs/migration/quill-triage.md)
- [Current GitHub issue triage](docs/project/issue-triage-1.3.0.md)
- [Support](SUPPORT.md)

## Provenance and license

Record is a standalone project based on the MIT-licensed history of
[digimata/quill](https://github.com/digimata/quill). Selected NewKap behaviors
were reimplemented natively. See [third-party notices](THIRD_PARTY_NOTICES.md)
for code and artwork attribution.

Record is available under the [MIT License](LICENSE).
