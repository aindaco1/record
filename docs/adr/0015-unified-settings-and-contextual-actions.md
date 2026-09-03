# ADR 0015: Unify durable settings and keep the menu action-oriented

- Status: accepted; Parakeet setup action amended by ADR 0017
- Date: 2026-09-02

## Context

Record's menu mixed immediate commands with persistent configuration for
exports, launch behavior, recording names, transcription, and built-in
capabilities. Screenshot support initially added a second preference window and
a second route to the same export-folder grant. That increased menu length and
made one durable destination appear to be two separate choices.

Private recovery material also needs a discoverable route without presenting a
permanent command when no recovery work exists.

## Decision

Use one AppKit `SettingsWindowController` with General, Screenshots, and
Recording sections. General owns the shared **Save to** presentation, capture
privacy, and login registration. Screenshots owns still-image format, JPEG
quality, shutter sound, and global shortcuts. Recording owns completed-session
naming, local transcription engine setup, and optional on-device transcript
refinement.

The settings UI is an adapter over the existing preference stores,
security-scoped export bookmark, and system-service adapters. It does not create
a second destination, copy preference state, or change any privacy or network
boundary. Screenshot and completed recording output continue to use the same
approved export root.

Keep the menu focused on immediate actions: screenshot and recording commands,
Screen source, opening the last recording or video in Gifski, retrying a failed
transcription, checking for updates, and quitting. Keep Screen source in the
menu because it changes the next capture action directly. Show **Open Recovery
Folder** only when the private recovery root contains a direct, non-symbolic-link
session directory with a manifest. Reuse the same recording presentation policy
to disable settings controls while their underlying configuration is locked.

## Consequences

From 1.4, generate the embedded menu-bar camera from the same canonical SVG as
the app icon. Keep the camera an adaptive AppKit template. A separate,
noninteractive Core Animation layer provides a visible red recording dot;
only that dot animates. The existing recording presentation controls its
lifecycle, including pause, stop, and screenshot feedback. Reduce Motion uses
a steady dot. This changes presentation without adding a timer or a second
recording state machine.

- Record exposes one destination choice and one settings surface without
  migrating or duplicating persisted state.
- The menu is shorter while operational capture and recovery actions remain
  directly available.
- Recovery-folder visibility reflects private session evidence and ignores
  unrelated files, nested impostors, and symbolic links.
- UI layout and availability require deterministic regression tests in addition
  to manual inspection of the signed app.
- This change adds no external plugin host, account, analytics, upload client,
  cloud transcription, model downloader, or network entitlement.
- ADR 0017 later adds the explicit Parakeet download action to this same
  Recording settings surface through a separate sandboxed helper.
