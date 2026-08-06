# ADR 0003: Isolate plugins from capture

- Status: accepted
- Date: 2026-08-06

## Decision

Ship the six required NewKap behaviors as built-in plugins behind one typed
protocol. Recording-time effects activate transactionally and restore in
reverse order on normal stop, activation failure, or recovery.

Future third-party plugins run outside the capture process with a declarative
manifest and explicit filesystem, media-transform, clipboard, notification,
or application-launch capabilities. Network access is not a capability.

## Consequences

- Plugin failure cannot crash or block capture callbacks.
- Arbitrary npm, JavaScript, shell, or unsigned native code is not loaded into
  the main application.
- Silence Notifications, Hide Clock, Hide Desktop Icons, Rename Recording,
  Playback Speed, and Open in Gifski share the same lifecycle/export APIs.
- Built-in plugins are tested with the same public contract intended for the
  isolated host.
