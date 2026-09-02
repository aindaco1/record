# GitHub issue scope after Record 1.3.0

Reviewed September 2, 2026 against the shipped
[`v1.3.0`](https://github.com/aindaco1/record/releases/tag/v1.3.0) source,
public artifacts, hosted checks, and live GitHub tracker. This is the current
repository snapshot; older files in this directory are retained as historical
release-planning records.

No open issue describes an unimplemented software defect. The four open issues
track physical-hardware or pre-release-platform acceptance for behavior already
implemented and deterministically tested. Their live GitHub descriptions remain
canonical.

| Issue | Implemented state | Remaining acceptance |
|---|---|---|
| [#6](https://github.com/aindaco1/record/issues/6) Microphone route recovery | Debounced route recovery, bounded retries, monotonic timing, silence-filled gaps, and raw-input fallback ship. | Representative USB disconnect/reconnect, Bluetooth profile changes, and a call-length route change. |
| [#9](https://github.com/aindaco1/record/issues/9) ScreenCaptureKit source selection | Display, application, window, and custom-region recording ship; 1.3.0 also reuses the picker/resolver for screenshots. | Representative displays, source loss/removal, Space changes, and permission revocation in the signed app. |
| [#26](https://github.com/aindaco1/record/issues/26) Crash-safe pause/resume | Immutable segments, serialized rotation, passthrough finalization, and idempotent recovery ship. | Repeated pause/resume and forced termination at each live capture boundary. |
| [#45](https://github.com/aindaco1/record/issues/45) macOS 27 and Xcode 27 | The advisory hosted Xcode 27 compile/test lane is green while releases remain on stable Xcode with a macOS 15 target. | Runtime, TCC, hardware capture, login-item, update, and inactive-app Parakeet checks on a physical macOS 27 beta/RC Mac. |

Do not close these issues from deterministic CI, a macOS 26 smoke test, or the
successful 1.2.3-to-1.3.0 updater check alone. Acceptance comments must identify
the signed app, OS, hardware category, and observed outcome without including
captured content, transcripts, device identifiers, credentials, or private
paths.
