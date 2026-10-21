# ADR 0029: Keep voice processing and microphone gain control independent

## Status

Accepted for 1.5.1. Live meeting acceptance remains pending.

## Context

Apple's VoiceProcessingIO enables automatic gain control by default. Record's
audio-only path previously inherited that default while requesting minimum fixed
playback ducking. Investigating interference with another microphone client
requires changing gain behavior independently of echo cancellation. Disabling
gain does not establish that shared microphone routing or the other client's
outgoing audio will remain unchanged.

## Decision

- Retain the voice-processing policy from [ADR 0007](0007-capture-health-and-echo.md):
  enabled by default for System Default, with the existing raw-input recovery.
  [ADR 0030](0030-zoom-voice-processing-compatibility.md) adds a manual processing
  switch and automatic Zoom bypass independently of AGC.
- Default `mic_automatic_gain_control` to false in typed configuration, including
  files that omit this new optional field. Keep schema version 1 compatible.
- Offer **Automatically adjust microphone volume** in Settings → Recording.
  Persist an explicit local preference over the JSON baseline, including false.
  Disable the control during capture and for routes that bypass voice processing.
- Snapshot the choice for each microphone recorder. On every processed engine
  setup, enable voice processing, explicitly apply the chosen AGC value, then
  retain minimum fixed other-audio ducking. Never bypass all voice processing
  merely to disable gain control.
- Apply this to audio-only recording and dictation. Explicit-device raw capture,
  ScreenCaptureKit microphone capture, and raw recovery do not acquire AGC.
- Do not write shared hardware gain, alter another application's settings, or
  change privacy, network, media preservation, or source separation boundaries.

## Consequences

Saved microphone speech may be quieter without automatic gain. Users can opt in
without losing echo cancellation. The choice remains stable through engine
recovery. Deterministic tests cover old/new defaults, persistence, Settings
locking, and adapter behavior without TCC or recording hardware. Real built-in
microphone/speaker behavior and remote-received Zoom quality remain manual
acceptance items in [the testing guide](../testing.md#microphone-gain-control).
