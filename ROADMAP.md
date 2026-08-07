# Roadmap

Record 1.0 intentionally focuses on dependable main-display and audio capture.
Priorities may change as real recordings expose better opportunities.

## 1.0.3 reliability

- Bounded off-callback microphone and system-audio writers with persistent,
  content-free per-track health events.
- Default-input route recovery with debounce, bounded retry, and timeline gaps
  represented by silence rather than compressed time.
- Media-aware interrupted-session recovery and byte-preserving quarantine.
- Reversible high-confidence transcript echo suppression while separate raw
  microphone and system tracks remain unchanged.

## 1.1.0

- Display, window, application, and region source selection.
- Pause and resume with lossless segment concatenation.
- Representative USB, Bluetooth, and call-length microphone-route acceptance.

## Next

- First-class microphone and frame-rate selection.
- A settings window for output, transcription, and plugin preferences.
- Direct source selection and pause/resume acceptance tests on real hardware.

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
- A lightweight manifest-derived recording history and configurable global
  shortcuts with conflict reporting and an explicit off state.
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
