# ADR 0014: Reuse local capture and export boundaries for screenshots

## Context

Record already has privacy-aware ScreenCaptureKit display filters, Apple's
window/application picker, a display-local area overlay, and a persistent
security-scoped export-folder grant. Screenshot support needs different output
sizing and publication semantics, but duplicating those selectors or grants
would create policy drift and retain more source metadata.

## Decision

Add three typed screenshot commands in `RecordCore`: full display, window or
application, and area. Menu actions and editable Carbon global hotkeys issue
those same commands. Carbon registration requires no Accessibility event tap;
an unregistered conflict remains visible in Screenshot Settings and each
shortcut can be Off.

Resolve still-image filters through the same `RecordCapture` resolver used by
recording streams. Full-display capture chooses the display containing the
pointer. Window/application capture uses Apple's picker, while area capture
reuses the existing noncapturing overlay. Opaque filters and geometry remain
memory-only.

Capture one native-resolution SDR image with `SCScreenshotManager`, excluding
the cursor and retaining window shadows. Encode and validate off the main
actor. Atomically publish lossless PNG by default or 95%-quality JPEG with
transparent pixels flattened onto white. Independently place lossless PNG data
on the local pasteboard. Use the existing approved export-folder bookmark and
do not create a screenshot session, manifest, preview, or history database.

Play the bundled CC0 shutter cue only after pixels are captured and only when
no recording is active. Complete success uses a brief menu-bar flash; failures
use content-free notifications. Only one screenshot operation may run at once,
but an operation may run alongside a stable recording.

## Consequences

- Recording and screenshot selection/privacy behavior stay DRY while native
  screenshot dimensions remain independent from video encoder bounds.
- Clipboard and disk publication can succeed or fail separately without
  discarding the successful local result.
- Screenshot settings are focused; transcription and plug-in controls retain
  their existing menus.
- Scrolling capture, repeat-area memory, delay, OCR, annotations, previews,
  pinning, editing, and screenshot history remain out of scope.
- The feature adds no account, analytics, cloud processing, upload client,
  model download, or network entitlement.
