# ADR 0028: Dictation and local recording control

- Status: accepted; shipped in 1.5.0
- Date: 2026-10-04

## Shared recording and transcription

Quick Dictation uses the existing audio recording session with microphone enabled
and system audio disabled for that session. It preserves the user's saved source
preferences, microphone selection, language, cleanup and vocabulary. Its shortcut
is a start/stop toggle; holding a key does not create repeated sessions. The
compact recording panel also appears for dictation. Closing it never stops capture.

Manifest schema 3 adds optional `purpose: "dictation"`. Only a single microphone
track can carry this purpose. Schemas 1 and 2 remain readable. Finalization,
export and recovery preserve the purpose. Like explicit audio imports, dictation
runs through the existing serial transcription coordinator even when automatic
transcription of ordinary recordings is disabled. No separate capture engine,
queue, vocabulary store or transcript database is introduced.

The preview reads the canonical transcript with the same bounded, regular-file,
no-symlink reader as Sessions. It displays segment text without timestamps or
speaker labels. Copy is explicit; Record does not paste, type into another app,
or change the clipboard automatically. Original audio and raw, cleaned and final
transcripts remain available through the existing preservation and retry paths.
While a dictation is awaiting transcription, its shortcut reopens that preview.
Deferring it in Sessions releases the pending preview for another dictation.

## One command policy and capture owner

RecordCore defines Start, Stop, Pause, Resume and Status with a closed mode enum
(screen, audio, dictation) and coarse phase snapshot. AppController derives that
snapshot from its existing capture tasks; it remains the sole capture owner.
Commands describe the desired state rather than toggle it. Repeating an accepted
command is a no-op when the app is already reaching or in that state. Conflicting
starts or transitions fail busy. Pause/resume apply only to screen recording.
Stopping during permission preparation cancels the pending start before capture.

Responses acknowledge acceptance, not completed capture or export. Status reports
preparing, recording, pausing, paused, resuming, stopping, saving or idle. It
contains no session paths, names, source devices, media or transcripts. The CLI
requires the running app and completed setup; interactive source selection and
permission/model setup stay in the app. Screen starts through CLI require the
saved Main Display source. Commands never download a model.

## Private local transport

Two invocations of the same sandboxed executable communicate through fixed files
in `RecordControl-v1` in the app's private cache. The directory is owner-only,
and regular-file, owner, link-count, no-symlink and 2 KiB bounds apply to reads.
Separate process locks allow one app server and one outstanding CLI request.
Atomic request/response files contain only typed commands, instance/request UUIDs,
an expiry and coarse state. A filesystem event wakes the main app. The CLI waits
at most four seconds for its matching response. Requests expire after five seconds
and cannot survive a server-instance change; an unconfirmed response tells the
caller to check status before retrying. A readable stale endpoint is insufficient
without a live server lock. Files are overwritten rather than accumulated.
The existing permission relaunch explicitly releases server ownership before
opening its replacement. A failed relaunch reacquires ownership with a fresh
instance UUID; old queued commands remain invalid.

This is a same-app, local-user channel, not authentication against other processes
already able to modify that user's private files. No socket, incoming or outgoing
network entitlement, public URL handler, app group, daemon, arbitrary path,
configuration argument or shell command is added. Existing TCC, export grants,
capture containment and source-preservation checks still apply.

## Apple Shortcuts and packaging

Five App Intents call the same AppController handler. They open Record so capture
continues to belong to the app, and return only the localized phase. Start accepts
the same three modes; permission and source-selection UI remains interactive.
Shortcuts does not receive transcript or media output from these actions.

The assembler uses the same Swift Build system as validation, then extracts
App Intents metadata from that exact release compilation. Packaging requires
all five actions and the three modes. Intent titles reuse the native interface
catalog; five shortcut phrases have English and neutral Latin American Spanish
translations. Entitlements and helper-service boundaries are unchanged.

## Acceptance

Deterministic tests cover command idempotence, CLI validation, private mailbox
round trips and unsafe inputs, shared intent dispatch, schema compatibility,
dictation recovery with automatic transcription off, vocabulary and source
preservation. Native signed-app execution, actual shortcut discovery, TCC and
hardware behavior remain separate checks in [the manual matrix](../testing.md)
and [candidate evidence](../testing/1.5.0-candidate.md).
