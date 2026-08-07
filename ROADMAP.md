# Roadmap

Record 1.0 intentionally focuses on dependable main-display and audio capture.
Priorities may change as real recordings expose better opportunities.

## 1.0.1 maintenance

- Guided, hash-verified import for the default Parakeet v3 model.
- Stable signing-identity enforcement so privacy grants survive updates.
- Reliable native Open at Login registration and optional-engine discovery.

## Next

- Display, window, application, and region source selection.
- Pause and resume with lossless segment concatenation.
- First-class microphone and frame-rate selection.
- Recovery UX for interrupted but salvageable sessions.
- A settings window for output, transcription, and plugin preferences.
- Automated update-feed integration tests using an isolated local fixture.
- Direct source selection and pause/resume acceptance tests on real hardware.

## Later

- Camera overlay with reconnect-safe device handling.
- Non-destructive trim, crop, mask, and annotation operations.
- Export presets with transparent format and quality tradeoffs.
- A capability-limited, out-of-process extension protocol.
- Optional cursor-click visualization and per-source audio controls.
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
