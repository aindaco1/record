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

`CommonMediaTimeline` uses one immutable host-time anchor without rewriting raw
presentation timestamps. It preserves real gaps and rejects samples before the
anchor or behind the last timestamp for their track.

The default capacities are three raw video frames and 32 buffers for each audio
track. Video is constrained to `1...8` because raw 4K frames are expensive;
audio is constrained to `1...128`. Changing those limits requires measurement
on the hardware performance matrix rather than allowing accidental unbounded
configuration.
