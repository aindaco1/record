# ADR 0019: Preserve selected source scope and observe its lifetime

## Context

Signed-app acceptance on macOS 26.6.2 found that the system picker returned an
application-only filter with a display-bound style and one included application.
Treating its style as a full-display choice rebuilt and widened that filter,
capturing an unrelated synthetic application's window. Preserving the original
filter corrected the isolation failure, but the application-filtered `SCStream`
still continued recording after its source process exited. Audio callbacks kept
the session alive without a source-loss delegate error. Frame
inactivity cannot establish source loss: an unchanged, hidden, minimized, or
off-Space window is a valid source.

## Decision

Resolve picker scope with a pure `RecordCore` policy before sizing or resolving
its content. A display-bound filter with included applications or windows is a
narrow selection. Preserve that opaque filter in the shared recording/screenshot
resolver; only a verified whole-display selection may be rebuilt through the
existing capture-privacy policy. When public inclusion-list inspection is
unavailable on macOS 15.0–15.1, reject ambiguous display-bound selections rather
than widen them. Main Display and direct region recording remain available.

Keep the selected application process identifiers alongside the memory-only
capture filter. Derive explicit-source identities from the already resolved
shareable-content inventory; use the public filter inspection API for system
picker selections on macOS 15.2 and later. Do not enumerate a substitute source
or persist these identifiers, application names, or window titles.

Before starting each stream, register a scoped `NSWorkspace` termination observer
and check whether the selected processes still exist. A pure `RecordCore`
lifetime policy emits one sanitized `sourceUnavailable` failure when the last
selected process exits. The existing capture failure, stop, segment finalization,
and recovery paths own cleanup. Remove observation before intentional stop or
cancellation, and also when the prepared stream is released.

## Consequences

- Source termination does not leave an audio-only half-session recording.
- No new permissions, entitlements, dependencies, network access, persisted
  source metadata, or work on sample callbacks are required.
- Display and region capture are unaffected by unrelated application exits.
- On macOS 15.0–15.1, explicitly narrow picker selections still rely on
  ScreenCaptureKit's delegate for source termination. Ambiguous display-bound
  selections fail before recording starts.
- Closing a window while its owner remains alive still relies on native stream
  source-loss behavior. Window hiding and Spaces transitions are not interpreted
  as application termination.
- Deterministic policy and notification-adapter tests complement signed-app
  acceptance with a disposable synthetic application on a virtual display.
