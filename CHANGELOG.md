# Changelog

All notable changes to Record are documented here. Record follows
[Semantic Versioning](https://semver.org/spec/v2.0.0.html) and the structure of
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Changed

- Added a direct, versioned GitHub release download for the verified Parakeet
  v3 model pack, while retaining explicit local import and the main app's
  no-network boundary.
- Refreshed current-state, privacy, security, architecture, testing, release,
  roadmap, and support documentation after the 1.3.0 publication and updater
  acceptance pass. Historical triage snapshots are now clearly separated from
  the live tracker.

## [1.3.0] - 2026-09-02

### Added

- Added native-resolution screenshots for the display under the pointer,
  Apple-selected windows or applications, and a custom selected area.
- Added editable global shortcuts, defaulting to Command-Shift-1,
  Command-Shift-2, and Command-Shift-4, plus a Screenshots section in the
  unified Settings window with an explicit Off state and shortcut-conflict
  guidance.
- Added immediate save to the existing approved export folder and independent
  lossless-PNG clipboard publication. Disk export defaults to lossless PNG and
  optionally supports JPEG at a default 95% quality with transparency
  flattened onto white.
- Added a brief menu-bar success flash and an optional CC0 shutter sound. The
  sound is automatically suppressed during active recordings.

### Changed

- Reused the existing Apple content picker, custom-area overlay, capture
  privacy policy, export-folder bookmark, and ScreenCaptureKit filter resolver
  for screenshots instead of creating parallel selection or storage systems.
- Screenshots preserve native source dimensions rather than inheriting the
  bounded 4K/even-dimension video profile.
- Window/application screenshots use Apple's selection-scoped permission
  directly; broad Screen Recording access is requested only for full-display
  and custom-area capture.
- Consolidated shared export-folder, capture-privacy, screenshot, recording-name,
  transcription, and login preferences into one Settings window. The menu now
  keeps immediate actions, retains Screen source, and shows Open Recovery
  Folder only when private session material exists.

### Fixed

- Full-display, area, and Apple-picker screenshots can include Record's own
  windows, while screen recordings retain their own-app exclusion and area
  selection overlays are dismissed before pixels are captured.
- Regression-tested unified Settings so the complete
  **Window or Application** label and footer controls remain visible.

### Security

- Screenshot pixels, selected-content filters, clipboard data, filenames, and
  export diagnostics remain local. The feature adds no account, analytics,
  upload, cloud processing, model download, or main-app network entitlement.

## [1.2.3] - 2026-08-31

### Changed

- Updated the commit-pinned CodeQL action from 4.37.7 to 4.37.9 and its
  default CodeQL bundle from 2.26.3 to 2.26.4.
- Centralized canonical session-media filenames, anonymous speaker defaults,
  local-file metadata checks, capture-kind mapping, and recording-menu
  presentation so audio-only, screen, recovery, export, transcription, and UI
  paths consume the same contracts.

### Fixed

- Restored Sparkle's release-only `generate_appcast` tool from the locked Swift
  package graph before signed-feed generation when reusing the exact CI app.
- Kept every conflicting recording configuration command disabled while Record
  is requesting permission, preparing capture, pausing, resuming, stopping, or
  saving, without relying on state left over from the previous menu phase.

### Security

- Reject symbolic links, directories, empty files, and non-file URLs through
  one shared local-artifact policy before audio inspection, Gifski handoff,
  recent-video restoration, session export, media concatenation, or interrupted
  session recovery can treat them as preserved recording media.

## [1.2.2] - 2026-08-27

### Changed

- Finalized microphone and system-audio tracks are now independent uncompressed
  24-bit PCM `mic.wav` and `system.wav` files. Record retains its AAC/CAF
  capture sources privately until the complete exported session validates.
- Reused the provenance-attested, package-tested unsigned app from the exact
  successful `main` CI commit during signed-tag releases. Release still stamps,
  signs, notarizes, packages, reads back, Sparkle-signs, checksums, attests, and
  publishes the same arm64 app contract while avoiding duplicate dependency
  resolution, tests, and production compilation.

### Fixed

- Preserved the measured microphone and system-audio start offsets when an
  audio-only session stops, before the live recorder adapters release their
  writer state.

### Security

- Required exact successful CI and CodeQL push runs, GitHub-hosted artifact
  provenance, bounded traversal-safe extraction, internal symlink containment,
  source and executable hashes, Xcode 26.3 identity, and an unsigned handoff
  before any protected release signing material is imported.

## [1.2.1] - 2026-08-26

### Added

- Added one silent, signed Sparkle feed check whenever Record opens. A newer
  release uses Sparkle's standard prompt, while downloading and installation
  remain user approved and **Check for Updates…** remains a manual fallback.

### Security

- Kept update networking inside Sparkle's sandboxed services, disabled
  automatic installation and system profiling, and retained the main app's
  no-network entitlements. Update requests include no recording, transcript,
  clipboard, session, diagnostic, model, local-path, or account data.

## [1.2.0] - 2026-08-25

### Added

- Added opt-in Apple Intelligence transcript readability refinement on
  supported macOS 26+ Macs. The on-device model can advise only on bounded
  filled-pause and immediate-repeat candidates; deterministic policy preserves
  timestamps and speaker labels and marks simultaneous speakers explicitly.
- Added reversible `transcript.raw.json` preservation for changed output plus a
  content-free, source-hashed `transcript.refinement.json` decision report.

### Changed

- Pinned authoritative CI and release jobs to Xcode 26.3 while retaining the
  macOS 15 deployment target and the advisory Xcode 27 compatibility lane.

### Security

- Kept Foundation Models processing on-device, added no network entitlement or
  model download path, escaped transcript context as untrusted data, and
  revalidated every generated decision before applying it.

## [1.1.3] - 2026-08-24

### Changed

- Updated FluidAudio from 0.15.5 to 0.15.6 for the latest offline Parakeet and
  speaker-diarization maintenance while retaining Record's fail-closed offline
  policy and verified local-model import.
- Updated the pinned CodeQL action from 4.37.6 to 4.37.7 and its CodeQL bundle
  from 2.26.2 to 2.26.3.

### Security

- Updated Sparkle from 2.9.5 to 2.9.6 for upstream installer hardening,
  including safer archive movement and rejection of package installs after
  signing validation fails. Record still permits only explicit manual update
  checks through Sparkle's sandboxed services; the main app retains no network
  entitlement.

## [1.1.2] - 2026-08-17

### Changed

- Added a standard Applications shortcut to the notarized DMG for a clear
  drag-to-install flow and compatibility with cautious single-app DMG handlers.
- Added one shared, fail-closed DMG layout contract used before image creation,
  during local package checks, and after signing, notarization, and stapling.
  Final release validation now checks image integrity, the exact mounted layout,
  the app bundle contract, signatures, entitlements, TCC identity, notarization
  tickets, and Gatekeeper acceptance before publication.
- Added a direct Apple Silicon DMG link while retaining the full release page
  for checksums, release notes, build metadata, and provenance.

## [1.1.1] - 2026-08-07

### Fixed

- Marshal ScreenCaptureKit picker selection, cancellation, and presentation
  failure callbacks from ReplayKit's XPC queue onto the main actor. This
  prevents Swift 6 isolation traps after choosing a display, application, or
  window and allows the custom-region overlay to open after choosing a display.
- Resolve custom-region displays without guessing on ambiguous multi-display
  layouts, and let the borderless selection overlay become key before assigning
  its first responder so it reliably receives drag and Escape events.
- Restore the newest valid screen recording after relaunch so **Open Last Video
  in Gifski** remains available even when the newest session is audio-only.

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

[Unreleased]: https://github.com/aindaco1/record/compare/v1.3.0...HEAD
[1.3.0]: https://github.com/aindaco1/record/compare/v1.2.3...v1.3.0
[1.2.3]: https://github.com/aindaco1/record/compare/v1.2.2...v1.2.3
[1.2.2]: https://github.com/aindaco1/record/compare/v1.2.1...v1.2.2
[1.2.1]: https://github.com/aindaco1/record/compare/v1.2.0...v1.2.1
[1.2.0]: https://github.com/aindaco1/record/compare/v1.1.3...v1.2.0
[1.1.3]: https://github.com/aindaco1/record/compare/v1.1.2...v1.1.3
[1.1.2]: https://github.com/aindaco1/record/compare/v1.1.1...v1.1.2
[1.1.1]: https://github.com/aindaco1/record/compare/v1.1.0...v1.1.1
[1.1.0]: https://github.com/aindaco1/record/compare/v1.0.3...v1.1.0
[1.0.3]: https://github.com/aindaco1/record/compare/v1.0.2...v1.0.3
[1.0.2]: https://github.com/aindaco1/record/compare/v1.0.1...v1.0.2
[1.0.1]: https://github.com/aindaco1/record/compare/v1.0.0...v1.0.1
[1.0.0]: https://github.com/aindaco1/record/releases/tag/v1.0.0
