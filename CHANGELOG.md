# Changelog

All notable changes to Record are documented here. Record follows
[Semantic Versioning](https://semver.org/spec/v2.0.0.html) and the structure of
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

## [1.1.1] - 2026-08-07

### Fixed

- Marshal ScreenCaptureKit picker selection, cancellation, and presentation
  failure callbacks from ReplayKit's XPC queue onto the main actor. This
  prevents Swift 6 isolation traps after choosing a display, application, or
  window and allows the custom-region overlay to open after choosing a display.

## [1.1.0] - 2026-08-07

### Added

- A persistent **Screen source** mode with the main-display fast path, Apple's
  display/application/window picker, and a display-local custom-region overlay.
- An advisory Xcode 27 / Swift 6.4 CI lane and a signed-app macOS 27 beta/RC
  compatibility gate without raising Record's macOS 15 deployment target.
- Crash-safe screen-recording pause/resume with immutable video, system-audio,
  and microphone segments plus a captured-time menu counter.

### Changed

- Final screen export joins compatible HEVC segments through AVFoundation's
  passthrough composition and remuxes AAC packets into the canonical CAF files
  without re-encoding either audio source.
- The macOS release gate now health-checks rootless Podman through a user-level
  launchd watchdog, preventing automation process cleanup from terminating the
  VM or its `gvproxy` bridge.

### Security

- System-picker filters remain memory-only: Record persists only the selection
  mode and never stores application names, window titles, source identifiers,
  or region geometry.
- Pause/resume journals contain only segment indices, relative times, track
  kinds, and local filenames; captured content and source metadata never enter
  the manifest or CI logs.

## [1.0.3] - 2026-08-07

### Added

- Extracted Record's offline Parakeet runtime and bounded offline speaker
  diarization adapter into the reusable `RecordSpeech` library product. Record
  continues to use the same local-only implementation through a thin app
  adapter, and sibling Dust Wave tools can reuse it without forking model code.
- Content-free per-track capture health events for missing callbacks, digital
  silence, route recovery, bounded-queue pressure, and write failures.
- Crash recovery that validates media containers, promotes playable partials,
  and quarantines invalid partials without deleting their bytes.
- Conservative cross-track transcript echo suppression with the unsuppressed
  result retained locally as `transcript.raw.json`.

### Changed

- Microphone and system-audio callbacks now hand buffers to fixed-capacity
  writer queues instead of performing codec and filesystem work inline.
- Microphone voice processing is enabled by default; input-device changes
  debounce, restart into the same track, retry on failure, and pad route gaps
  to keep the recorded timeline monotonic.
- Completion hooks use a local exclusive claim marker for at-most-once launch
  across crash recovery.
- Renamed the menu labels to **Transcript model** and **Select export folder…**.

### Fixed

- Preserve source audio duration when FluidAudio reports a zero-duration
  Parakeet result.
- Stop repeated microphone graph restarts after a headphone route change;
  unhealthy VoiceProcessingIO routes now fall back once to raw capture and
  retain the full timeline.
- Remove exact one- or two-word echo fragments when longer aligned echo
  segments prove they belong to one continuous speaker-bleed run.
- Start audio-only capture with the process tap that successfully requested
  permission, and ignore the microphone graph's own startup configuration
  notification instead of rebuilding both Core Audio paths before recording.

### Security

- Registered the existing local release-signing public key with GitHub as an
  SSH signing key; no private key material was copied or uploaded.

## [1.0.2] - 2026-08-07

### Added

- **Open last recording** reveals the newest finalized or interrupted session
  from approved storage without maintaining a separate history database.
- Interrupted-session recovery posts one content-free summary notification with
  direct access to temporary recovery storage.
- Failed local transcriptions expose an explicit one-click retry action without
  requiring Record to restart or modifying the recording.

### Changed

- Consolidated speculative feature epics into the ROADMAP so the active issue
  backlog represents concrete reliability and distribution work.
- Removed the final stale LaunchAgent reference from the SwiftPM manifest.

## [1.0.1] - 2026-08-07

### Added

- Missing-model detection plus a guided, verified Parakeet v3 local import.
- A release gate that preserves Record's bundle identifier, Apple signing
  team, hardened runtime, and designated requirement across updates.

### Fixed

- Open at Login remains actionable when ServiceManagement initially reports
  `.notFound` for an app that is already installed in Applications.
- MacWhisper appears only when MacWhisper, its `mw` CLI, and Record's sandbox
  helper are all present; an unavailable saved selection returns to Parakeet.

### Upstream

- Submitted a FluidAudio manifest fix so its Parakeet benchmark Markdown file
  can be excluded from SwiftPM source discovery in the next dependency update.

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

[Unreleased]: https://github.com/aindaco1/record/compare/v1.1.1...HEAD
[1.1.1]: https://github.com/aindaco1/record/compare/v1.1.0...v1.1.1
[1.1.0]: https://github.com/aindaco1/record/compare/v1.0.3...v1.1.0
[1.0.3]: https://github.com/aindaco1/record/compare/v1.0.2...v1.0.3
[1.0.2]: https://github.com/aindaco1/record/compare/v1.0.1...v1.0.2
[1.0.1]: https://github.com/aindaco1/record/compare/v1.0.0...v1.0.1
[1.0.0]: https://github.com/aindaco1/record/releases/tag/v1.0.0
