# Record

Record is a local-first screen and audio recorder for macOS. Capture your
screen, take screenshots, dictate a quick note, or transcribe audio files
without sending the content to a cloud service.

Microphone and system audio stay in separate files. Browse recordings and
transcripts in Sessions, apply custom vocabulary, and control recording from
keyboard shortcuts, Apple Shortcuts, or the terminal. Finished media is saved
to a folder you choose, with Desktop suggested on first use.

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
open the notarized DMG, and drag **Record** onto its Applications shortcut.
Releases are Developer ID signed, notarized, and accompanied by
SHA-256 checksums and build provenance on the
[GitHub release page](https://github.com/aindaco1/record/releases/latest).

The [latest release page](https://github.com/aindaco1/record/releases/latest)
lists the current version, build, release notes, and verified downloads.

Record has no Dock icon. Open it from the camera in the menu bar.

## Use

1. Open **Settings… → General** and choose a save folder with **Change…**.
2. In **Recording**, choose screen or audio-only mode, select your audio sources
   and microphone, and use **Test Input** before starting.
3. In **Transcription**, set up the local model and add any preferred spellings.
   Recording works before model setup; transcription waits until it is ready.
4. Open **Sessions** to review recordings, copy transcripts, retry unfinished
   work, or import audio files.

For a short spoken note, choose **Quick Dictation**, stop when finished, then
review and copy the text. For screenshots, use the menu's full-display,
window/application, or area capture commands. Configure keyboard shortcuts in
**Settings… → Shortcuts**.

See the [user guide](docs/user-guide.md) for screenshot shortcuts, recording
sources, settings, recovery, transcription options, updates, and uninstalling.

## Privacy and security

Record keeps screenshots, recordings, transcripts, clipboard content,
clipboard-derived names, and raw diagnostics local. It has no accounts, analytics,
media uploads, or cloud transcription. **Help & diagnostics…** lets you review,
save, and explicitly send a filtered report to the developer. Submitted reports
are public. The sandboxed main app has no incoming or outgoing network entitlement.

Network access is limited to sandboxed helpers for signed application updates,
the fixed Parakeet model download, and reviewed diagnostic submission after
explicit user action. Selecting MacWhisper extends the local trust boundary to
that separately installed app.
See the [privacy policy](docs/PRIVACY.md) for data handling, the
[security policy](docs/SECURITY.md) for private reporting, and the
[local-only boundary](docs/security/local-only-boundary.md) for enforcement.

## Development

Development requires Xcode 27 or newer and Swift 6. Start with the
[contributor guide](docs/CONTRIBUTING.md) for build, validation, local app launch,
and dependency-review procedures.

## Documentation

The [documentation index](docs/README.md) covers user guides, architecture,
security, testing, releases, and historical records. Useful starting points:

- [User guide](docs/user-guide.md)
- [Support](docs/SUPPORT.md)
- [Architecture](docs/architecture.md)
- [Roadmap](docs/project/roadmap.md)
- [Changelog](CHANGELOG.md)
- [Record 1.5.0 release notes](docs/releases/1.5.0.md)

## Provenance and license

Record is a standalone project based on the MIT-licensed history of
[digimata/quill](https://github.com/digimata/quill). Selected NewKap behaviors
were reimplemented natively. See [third-party notices](THIRD_PARTY_NOTICES.md)
for code and artwork attribution.

Record is available under the [MIT License](LICENSE).
