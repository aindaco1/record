# Changelog

All notable changes to Record are documented here. Record follows
[Semantic Versioning](https://semver.org/spec/v2.0.0.html) and the structure of
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

## [1.0.0] - 2026-08-07

### Added

- Native Apple-Silicon menu-bar app for macOS 15 and newer.
- Main-display screen capture with a video-only HEVC MOV plus independent
  microphone and system-audio CAF tracks.
- Audio-only recording with the same independently recoverable audio tracks.
- Command-scoped permission requests and one-shot recovery after a privacy
  setting restarts the app.
- Atomic Desktop export through a persisted security-scoped folder grant.
- Local Parakeet v3 transcription and optional, explicitly selected
  MacWhisper integration.
- Capture-privacy, recording-name, and Gifski handoff plugins.
- Human-readable local notifications that open the exported session in Finder.
- Manual signed update checks through Sparkle and an optional native Open at
  Login setting.
- Developer ID signing, Apple notarization, checksums, provenance attestations,
  CodeQL, dependency review, sanitizer tests, and Podman-based linting.

### Security

- App Sandbox with no main-app network entitlement, app-scoped bookmarks, and
  narrowly scoped Sparkle XPC services for explicit update checks.
- Ed25519 signatures for the update archive and feed, in addition to Developer
  ID signing and notarization.
- Offline model enforcement and fail-closed validation for optional external
  tools.

[Unreleased]: https://github.com/aindaco1/record/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/aindaco1/record/releases/tag/v1.0.0
