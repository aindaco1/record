# ADR 0002: Enforce a local-only data boundary

- Status: accepted; update cadence amended by ADR 0011 and screenshot handling
  specified by ADR 0014
- Date: 2026-08-06

## Decision

Record does not send screenshot pixels, recording content, transcripts,
metadata, clipboard content, or diagnostics over the network. It has no
account, telemetry, cloud transcription, collaboration, or upload subsystem.

Transcription engines load assets already present on disk. Models may be
bundled with a release or imported through an explicit local-file workflow;
the recording application does not fetch them.

Record may check for software updates once at launch or after an explicit user
command. ADRs 0004 and 0011 confine those requests to Sparkle's sandboxed
downloader service and require a signed GitHub release feed and signed archive.
No screenshot, recording content, transcript, identifier, local path, or
diagnostic is part of a request.

## Consequences

- Quill PR #3 (AssemblyAI) is rejected.
- The stale NewKap Giphy configuration is not migrated.
- Remote wallpaper URLs from the old desktop-icons plugin are not supported.
- Network dependencies in core product targets require a new ADR and explicit
  user approval; Sparkle is the reviewed update-only exception in ADRs 0004
  and 0011.
- Signed app artifacts enable App Sandbox but intentionally omit client and
  server network entitlements. CI verifies the embedded signing policy.
- CI may access package and tool registries; CI never processes user media.
