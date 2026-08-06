# ADR 0002: Enforce a local-only data boundary

- Status: accepted
- Date: 2026-08-06

## Decision

Record does not send recording content, transcripts, metadata, clipboard
content, or diagnostics over the network. It has no account, telemetry, cloud
transcription, collaboration, or upload subsystem.

Transcription engines load assets already present on disk. Models may be
bundled with a release or imported through an explicit local-file workflow;
the recording application does not fetch them. Software installation and
updates happen outside Record through GitHub or Homebrew.

## Consequences

- Quill PR #3 (AssemblyAI) is rejected.
- The stale NewKap Giphy configuration is not migrated.
- Remote wallpaper URLs from the old desktop-icons plugin are not supported.
- Network dependencies in core product targets require a new ADR and explicit
  user approval.
- Signed app artifacts enable App Sandbox but intentionally omit client and
  server network entitlements. CI verifies the embedded signing policy.
- CI may access package and tool registries; CI never processes user media.
