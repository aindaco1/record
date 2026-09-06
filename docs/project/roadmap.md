# Roadmap

Record prioritizes dependable local capture. This page describes current
direction and deferred ideas. See the [changelog](../../CHANGELOG.md) and
[release notes](../releases/) for shipped work. The
[GitHub tracker](https://github.com/aindaco1/record/issues) holds live issue
status; versioned issue-triage files are historical planning snapshots.

## Next

- First-class microphone and frame-rate selection.
- Representative USB, Bluetooth, and call-length microphone-route acceptance.
- Direct source-selection and pause/resume acceptance tests on real hardware.
- macOS 27 runtime/TCC and inactive-app transcription acceptance on physical
  hardware; the hosted Xcode 27 preview lane remains advisory.

## Parked ideas

These are useful possibilities, not active commitments. They do not need open
umbrella issues until a real use case justifies the complexity.

- Camera overlay with reconnect-safe device handling.
- Non-destructive trim, crop, mask, and annotation operations.
- Export presets with transparent format and quality tradeoffs.
- A capability-limited, out-of-process extension protocol.
- Optional cursor-click visualization and per-source audio controls.
- Optional first-party Whisper/translation if MacWhisper stops meeting the need.
- An opt-in local browser speaker-metadata bridge.
- Content-free, end-to-end local speech progress through one engine-independent
  contract, with deterministic long-file, two-track, and failure tests; exact
  speaker-count constraints only when a real offline-diarization consumer and
  representative fixtures justify them.
- A lightweight manifest-derived recording history.
- Localization and VoiceOver-focused accessibility review.

## Non-goals

- Accounts, analytics, recording uploads, cloud transcription, or remote
  collaboration.
- Electron, an embedded browser UI, or arbitrary extension code inside the
  capture process.
- Intel Mac or pre-macOS 15 compatibility for the 1.x line.

Performance work remains continuous: bounded memory and queues, measured frame
drops, stable A/V timing, fast finalization, and recoverable media take priority
over adding editing surface area.
