# Roadmap

Record prioritizes dependable local capture. This page describes current
direction and deferred ideas. See the [changelog](../../CHANGELOG.md) and
[release notes](../releases/) for shipped work. The
[GitHub tracker](https://github.com/aindaco1/record/issues) holds live issue
status; versioned issue-triage files are historical planning snapshots.

## Current release and follow-up

[Record 1.5.0](../releases/1.5.0.md) ships microphone/source selection, Sessions,
custom vocabulary, multi-file transcription, English/Spanish UI, Quick Dictation,
and CLI/Apple Shortcuts recording controls. See the
[validation record](../testing/1.5.0-candidate.md#public-release-verification)
for what was exercised in the public app.

Remaining acceptance work includes USB/Bluetooth input loss, external displays,
call-length recording, clean-account and permission-revocation flows, physical
global shortcuts, full keyboard/VoiceOver coverage, and recorded-frame exclusion
of the compact panel. Keep these separate from completed automated, built-in
audio, model-installation, and updater checks.

First-class frame-rate selection remains planned. Shipped capture uses 30 fps.

## Parked ideas

These are useful possibilities, not active commitments. They do not need open
umbrella issues until a real use case justifies the complexity.

- Camera overlay with reconnect-safe device handling.
- Non-destructive trim, crop, mask, and annotation operations.
- Export presets with transparent format and quality tradeoffs.
- A capability-limited, out-of-process extension protocol.
- Optional cursor-click visualization and per-source volume controls.
- Optional first-party Whisper/translation if MacWhisper stops meeting the need.
- An opt-in local browser speaker-metadata bridge.
- Offline speaker labeling and speaker-count constraints, when a concrete use
  case and representative audio justify the added complexity.

## Non-goals

- Accounts, analytics, recording uploads, cloud transcription, or remote
  collaboration.
- Electron, an embedded browser UI, or arbitrary extension code inside the
  capture process.
- Intel Mac or pre-macOS 15 compatibility for the 1.x line.

Performance work remains continuous: bounded memory and queues, measured frame
drops, stable A/V timing, fast finalization, and recoverable media take priority
over adding editing surface area.
