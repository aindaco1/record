# ADR 0002: Enforce a local-only data boundary

- Status: accepted; update cadence amended by ADR 0011, screenshot handling
  specified by ADR 0014, and model acquisition amended by ADR 0017
- Date: 2026-08-06

## Decision

Record does not send screenshot pixels, recording content, transcripts,
metadata, clipboard content, or diagnostics over the network. It has no
account, telemetry, cloud transcription, collaboration, or upload subsystem.

Transcription engines load only verified assets already present on disk. ADR
0017 permits a separate sandboxed helper to fetch one pinned Parakeet release
asset after explicit user action; the recording process remains network-denied.

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
  user approval. Sparkle and the fixed Parakeet downloader are the reviewed XPC
  exceptions in ADRs 0004, 0011, and 0017.
- Signed app artifacts enable App Sandbox. The main app omits client and server
  network entitlements; CI separately enforces the model helper's minimal
  outbound-only entitlement.
- CI may access package and tool registries; CI never processes user media.
