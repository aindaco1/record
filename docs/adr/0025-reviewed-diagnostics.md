# ADR 0025: Explicitly reviewed diagnostic submission

- Status: accepted; user authorized the privacy exception on September 25, 2026
- Date: 2026-09-25
- Amends: ADR 0002 for the filtered report only; all raw user content stays local

## Decision

Adopt Paper's Help & diagnostics workflow using the already pinned Platform desktop
module. Record owns a closed `record-diagnostic-v1` projection, preview, local
pending storage and explicit consent. Platform owns incident projection, bounded
HTTPS transport and matching acknowledgement semantics. No automatic crash
collection, report submission, account or analytics is added.

Keep the main application without incoming/outgoing network entitlement. A dedicated
`RecordReportSender.xpc` has exactly sandbox and outbound-network entitlements,
no file grants, and a single data-only method. It accepts at most 8 KiB of canonical
schema-validated preview JSON and sends only to the compiled Record relay endpoint.
It cannot receive a URL, path, recording, transcript, raw incident or general request.
Imports are user-selected regular files bounded to 2 MiB, projected before storage.

The existing relay validates the same consumer-owned contract, reuses Platform's
`ReviewedReportGroup` and GitHub writer, and fixes the repository to `aindaco1/record`.
No new generic relay or transport is introduced. Retries keep the same report ID;
Refresh creates a new ID. Only a matching acknowledgement exposes an issue link.
The shared updater's busy guard prevents a manual update while submission is active.

## Consequences and validation

This is an explicit exception to the previous promise that every diagnostic stays
local. The [privacy policy](../PRIVACY.md) explains the exact projection, public
GitHub visibility, connection metadata and local/public retention. Raw content,
paths, names, session metadata and logs remain outside this exception.

The source gate rejects main-app transport calls, helper endpoint expansion and
file/general networking APIs. Deterministic tests exercise privacy projection,
retry identity and relay intake; packaging checks validate both helpers and the
unchanged main-app entitlement set. Full local gates, signed-app review and synthetic
live relay delivery remain separate required acceptance evidence.

## Rollback

Disable `RECORD_REPORTS_ENABLED` without deleting relay namespaces or migration
history. Revert the feature in a new monotonic release; do not move release tags.
The updater refactor from ADR 0024 can remain. Local saves and pending reports
contain only the filtered schema and never source recordings or raw crash files.
