# ADR 0030: Bypass Apple voice processing while Zoom is open

## Status

Accepted for 1.5.1. Remote Zoom hardware acceptance remains pending.

## Context

Apple VoiceProcessingIO can change the shared built-in microphone stream from
one channel to three quieter channels for ordinary capture clients. Record can
receive a healthy processed mono signal while another app's outgoing voice is
very quiet. Disabling AGC alone does not avoid this format change.

[Mozilla's engineering investigation](https://bugzilla.mozilla.org/show_bug.cgi?id=1910888#c5)
and [capture implementation](https://github.com/mozilla/cubeb-coreaudio-rs/commit/65f718b4234c97c5509248b0e2c39a07d9509f16)
use VPIO for their own affected capture clients. Record already uses that path;
it cannot force native Zoom to do the same. Volume compensation in Record would
not repair the microphone signal that Zoom receives.

## Decision

- Add **Use Apple voice processing** in Recording settings, default on, with a
  persistent Boolean override of the existing `mic_voice_processing` baseline.
- Add **Turn off while Zoom is open**, default on, with a persistent override of
  optional `mic_disable_voice_processing_for_zoom` (default true). Keep schema 1
  compatible. Retain the independent AGC policy in [ADR 0029](0029-independent-microphone-gain-control.md).
- Use a narrow AppKit adapter to check only the running native Zoom app identity
  `us.zoom.xos`. Observe workspace launch/termination notifications during eligible
  capture and subscribe before the initial snapshot. Check again before every
  engine attachment. Do not depend on the foreground app, which misses background
  calls. Do not infer meeting state, inspect windows, or enumerate audio clients.
- Keep the deterministic decision and per-capture bypass latch in RecordCore.
  Manual off and explicit input selection always win. Snapshot user preferences
  per microphone recorder, and lock controls while capture is busy.
- If Zoom is already running, never enable VPIO for that capture. If Zoom launches
  during processed capture, release the processed engine and use existing bounded
  route recovery to attach raw input to the same writer. Preserve source media,
  timeline padding, queue bounds, and stop/recovery cancellation.
- Once bypassed, remain raw through Zoom termination/relaunch and microphone route
  changes until capture ends. Reevaluate on the next capture. This avoids repeated
  interruptions from changing app state.
- Apply to audio-only recording and dictation. Explicit device capture and
  ScreenCaptureKit microphone capture keep their existing paths. The bypass is
  conservative for all System Default devices, rather than an unverified device
  allowlist. Users may opt out independently of the manual processing switch.
- Keep detection and diagnostic state local. Store no app inventory or meeting
  data. Add no permissions, entitlements, networking, shared hardware-gain writes,
  virtual audio devices, or changes to Zoom settings.

## Consequences

Idle/background Zoom also disables processing. Browser Zoom and other conference
apps are not detected. Raw input can contain more speaker echo and background
noise. Launching Zoom during capture can cause a short padded interruption and
cannot guarantee that Zoom never sees a transient during OS reconfiguration.
Quitting Zoom restores processing only on a later capture.

Tests cover defaults and persistence, UI locking, monitor lifecycle, manual and
explicit-device precedence, launch/quit/relaunch latching, and recovery decisions
without TCC or audio hardware. Validate actual microphone behavior and remote
speech using [the manual comparison](../testing.md#voice-processing-and-zoom-compatibility).
