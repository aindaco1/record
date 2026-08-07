# ADR 0009: Rotate immutable media for pause and resume

## Context

Pausing a live `SCStream` or keeping one long mutable writer open creates
ambiguous crash boundaries. Record must keep video, system audio, and microphone
independently recoverable, avoid callback work, and produce canonical files
without a generation-losing re-encode.

## Decision

Treat every active interval as a numbered immutable segment. Before a writer is
created, atomically append its expected filenames and start/resume event to the
session manifest. Pause stops the stream, drains the bounded sink, finalizes all
three writers, replaces the segment's expected tracks with its actual artifacts,
and then records the pause event. Resume repeats that process with the next
number and the same typed configuration plus memory-only source selection.

Stop serializes behind an in-flight rotation. It joins compatible video tracks
through `AVAssetExportPresetPassthrough`. Because `AVAssetExportSession` cannot
passthrough to CAF, audio uses `AVAssetReader` and `AVAssetWriter` with nil output
settings to copy existing AAC packets while shifting timestamps. No segment is
deleted or overwritten. Canonical files are promoted only after every output
finishes, and raw segments remain in private storage until whole-session export
validation succeeds.

The manifest retains content-free start, pause, resume, and stop events after
finalization but removes its working-segment inventory because exported sessions
contain only canonical tracks. Startup recovery considers both canonical tracks
and journaled segment tracks, including recognized hidden partials.

## Consequences

- Repeated pause/resume commands are idempotent; UI transitions disable racing
  commands, and session stop waits for active rotation work.
- Paused wall time and stream restart latency do not inflate the captured-time
  counter or final media timeline.
- A forced exit can lose only the unfinalized tail currently owned by an
  `AVAssetWriter`; playable partial recovery can promote that tail without
  changing completed segments.
- Finalization performs container and timestamp work proportional to the number
  of segments, but does not spend CPU/GPU time decoding and encoding media.
- Signed-app testing must still exercise source loss, forced quit, and repeated
  rotations with real ScreenCaptureKit/TCC behavior.
