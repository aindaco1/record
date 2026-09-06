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

The current release is [Record 1.4.0](https://github.com/aindaco1/record/releases/tag/v1.4.0),
build 17, published September 3, 2026.

Record has no Dock icon. Open it from the camera in the menu bar.

## Use

1. Choose **Settings… → General → Save to** to approve the destination for
   screenshots and completed recordings. Desktop is suggested on first use.
2. Choose **Capture Full Display**, **Capture Window or Application…**, or
   **Capture Area…** for a screenshot. Record saves the image and independently
   copies a lossless PNG to the clipboard.
3. Choose **Start screen recording** or **Start audio-only recording** to
   record. Microphone and system audio are exported as separate 24-bit PCM WAV
   files; screen sessions also include a video-only MOV.
4. For local transcription, follow the [Parakeet setup guide](docs/models/parakeet.md).
   Recording remains available while the model is absent.

See the [user guide](docs/user-guide.md) for screenshot shortcuts, recording
sources, settings, recovery, transcription options, updates, and uninstalling.

## Privacy and security

Record keeps screenshots, recordings, transcripts, clipboard content,
clipboard-derived names, and diagnostics local. It has no accounts, analytics,
uploads, or cloud transcription. The sandboxed main app has no incoming or
outgoing network entitlement.

Network access is limited to sandboxed helpers for signed application updates
and the fixed Parakeet model download after explicit user action. Selecting
MacWhisper extends the local trust boundary to that separately installed app.
See the [privacy policy](docs/PRIVACY.md) for data handling, the
[security policy](docs/SECURITY.md) for private reporting, and the
[local-only boundary](docs/security/local-only-boundary.md) for enforcement.

## Development

Development requires Xcode 26 or newer and Swift 6. Start with the
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
- [Record 1.4.0 release notes](docs/releases/1.4.0.md)

## Provenance and license

Record is a standalone project based on the MIT-licensed history of
[digimata/quill](https://github.com/digimata/quill). Selected NewKap behaviors
were reimplemented natively. See [third-party notices](THIRD_PARTY_NOTICES.md)
for code and artwork attribution.

Record is available under the [MIT License](LICENSE).
