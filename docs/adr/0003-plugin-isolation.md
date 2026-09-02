# ADR 0003: Isolate plugins from capture

- Status: accepted; shipped capability set clarified 2026-09-02
- Date: 2026-08-06

## Decision

Ship only small, capability-specific NewKap-inspired behaviors behind typed
interfaces rather than a general in-process plugin host. Recording-time capture
privacy effects activate transactionally and restore in reverse order on normal
stop, activation failure, or recovery. Recording naming and Gifski handoff use
the same validated session/export boundaries without pretending to be arbitrary
plugins.

Future third-party plugins run outside the capture process with a declarative
manifest and explicit filesystem, media-transform, clipboard, notification,
or application-launch capabilities. Network access is not a capability.

## Consequences

- Plugin failure cannot crash or block capture callbacks.
- Arbitrary npm, JavaScript, shell, or unsigned native code is not loaded into
  the main application.
- Notification, menu-bar, and Desktop-item capture privacy; finished-recording
  naming; and Gifski handoff are the shipped capability set.
- Playback speed remains a parked editor/export idea and is not part of the
  current app.
- Built-in capabilities are tested through narrow contracts that a future
  isolated host could reuse.
