# Bounded media ingress

`BoundedScreenCaptureSink` is the asynchronous boundary between native capture
callbacks and the future encoder/writer. Each input track has an independently
fixed capacity. Callback threads only take a short lock, retain the sample, and
schedule at most one drain operation.

When a track is full, Record evicts its oldest queued sample. This preserves the
newest capture state, caps latency and retained IOSurfaces, and exposes the loss
through `droppedForBackpressure`. It never waits for the encoder on a capture
callback.

The worker drains the earliest presentation timestamp currently available
across screen, system-audio, and microphone queues. `finish()` seals the sink,
waits for accepted work, and is safe to call repeatedly or concurrently. A
processor failure clears retained buffers, returns a sanitized typed failure,
and rejects later samples.

`IndependentMediaTimeline` validates that every track uses one capture-clock
epoch and rejects per-track timestamp regressions. Because ScreenCaptureKit's
three callback queues can deliver their first samples out of timestamp order,
each independent writer starts at its own first sample instead of treating the
first callback as a shared lower bound.

The media processor creates separate atomic destinations for the three queues:
video-only `recording.mov`, `system.caf`, and `mic.caf`. This preserves source
separation and prevents players from treating system and microphone audio as
alternative MOV tracks. The manifest records each track's offset from the
earliest first sample so downstream processing can restore alignment.

The default capacities are three raw video frames and 32 buffers for each audio
track. Video is constrained to `1...8` because raw 4K frames are expensive;
audio is constrained to `1...128`. Changing those limits requires measurement
on the hardware performance matrix rather than allowing accidental unbounded
configuration.
