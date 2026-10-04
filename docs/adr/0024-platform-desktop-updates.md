# ADR 0024: Shared desktop updater mechanics

Accepted 2026-09-25.

The updater decision below remains in effect. The later
[ADR 0025](0025-reviewed-diagnostics.md) adds shared diagnostics utilities and a
separate reviewed-report sender; its transport remains excluded from main-app use.

Record consumes Platform's separately scoped desktop Swift package for the
standard Sparkle controller and pure launch policy. It retains exact Sparkle
2.10.0, its lockfile, launch consent policy, update feed/key and sandbox.
Only the updater and policy products are linked; the shared diagnostics
network client is not a Record dependency. The local-only source guard scans
the shared targets that Record uses.

See [migration and rollback evidence](../SHARED_DESKTOP_MIGRATION.md).
