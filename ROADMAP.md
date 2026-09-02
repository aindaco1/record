# Roadmap

Record prioritizes dependable local capture. Shipped work is retained here for
context; the **Next** and **Parked ideas** sections describe current direction.

## Shipped

### 1.0.3 reliability

- Bounded off-callback microphone and system-audio writers with persistent,
  content-free per-track health events.
- Default-input route recovery with debounce, bounded retry, and timeline gaps
  represented by silence rather than compressed time.
- Media-aware interrupted-session recovery and byte-preserving quarantine.
- Reversible high-confidence transcript echo suppression while separate raw
  microphone and system tracks remain unchanged.

### 1.1.0

- Display, window, application, and region source selection.
- Pause and resume with lossless segment concatenation.
- macOS 27 / Xcode 27 compatibility validation without raising the macOS 15
  deployment target or moving signed releases onto a beta toolchain.

### 1.3.0

- Native-resolution PNG/JPEG screenshots for full display, Apple-selected
  window/application, and custom area.
- Immediate save to the shared approved export folder plus independent
  lossless-PNG clipboard publication.
- Editable global screenshot shortcuts with conflict reporting and Off states,
  plus screenshot controls in the unified Settings window and a recording-safe
  shutter cue.
- One Settings window for the shared export destination, capture privacy,
  screenshot options, login behavior, recording names, and transcription.

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
