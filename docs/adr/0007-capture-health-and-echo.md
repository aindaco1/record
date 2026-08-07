# ADR 0007: Preserve raw tracks and repair capture quality at explicit layers

## Status

Accepted for Record 1.0.3.

## Context

Speaker playback can leak into the microphone when headphones are absent. A
microphone route can also change or temporarily disappear during capture.
Deleting or destructively filtering a raw source would make either problem
harder to diagnose and could remove legitimate overlapping speech.

## Decision

- Keep `mic.caf` and `system.caf` independent and immutable.
- Enable Apple's local VoiceProcessingIO echo cancellation by default, with a
  raw-microphone fallback when a route produces digital zeros.
- Debounce route notifications through one state machine, restart into the
  same writer, retry at a fixed interval, and represent downtime with silence.
- Move encoding and filesystem writes behind fixed-capacity queues. Capture
  callbacks perform only a bounded owning copy and enqueue.
- Persist content-free health events in `session.json`; never include samples,
  recognized text, filenames, or device names.
- Apply a second safeguard only to transcript output. Suppress an aligned mic
  segment only when it contains at least three words and has high word-order
  agreement with overlapping system speech. Keep short backchannels and
  different overlapping speech. When anything is suppressed, write the full
  result to `transcript.raw.json` before publishing the cleaned transcript.

## Consequences

The readable transcript is less likely to repeat speaker dialogue without
making the source recordings lossy. Conservative matching can leave some echo,
which is preferable to deleting uncertain speech. Route gaps remain visible as
silence and in health metadata. The audio writer and recovery policy have
deterministic tests independent of hardware; actual device swaps remain part of
the signed-app hardware smoke test.
