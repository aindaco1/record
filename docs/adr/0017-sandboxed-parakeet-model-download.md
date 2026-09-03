# ADR 0017: Download the pinned Parakeet model through a sandboxed helper

- Status: accepted
- Date: 2026-09-02

## Context

Record 1.3.0 publishes a verified Parakeet v3 model pack as a separate GitHub
release asset, but the browser download, expansion, and folder-selection steps
still make first-run transcription setup unnecessarily difficult. The main
recording process must not gain general network capability or expose private
capture data to a downloader.

## Decision

Record 1.3.1 adds **Download and Install** to the existing Parakeet setup flow.
A bundled `RecordModelDownloader.xpc` service owns the only model-network code.
The main app retains no incoming or outgoing network entitlement and sends the
service only an open, private temporary-file descriptor. It sends no URL, path,
recording, transcript, clipboard value, identifier, diagnostic, or metadata.

The helper chooses the compile-time-pinned
`Record-Parakeet-v3-aed0274.zip` URL. It uses an ephemeral Foundation
`URLSession`, permits only HTTPS `github.com` and GitHub-controlled
`*.githubusercontent.com` redirects, stores no cookies or cache, and retries or
resumes a bounded number of transient connection failures. Its entitlements
contain exactly App Sandbox and outbound network client.

The helper verifies the archive's exact 465,779,146-byte size and SHA-256 before
writing it through the descriptor. The main process independently repeats that
verification, expands the archive into private temporary storage with an
absolute `/usr/bin/ditto` invocation and direct arguments, and reuses ADR 0005's
17-file allowlist, per-file size/SHA-256 verification, and atomic installation.
Manual folder import remains available. FluidAudio's own download surface
remains disabled.

Record 1.3.2 corrects the post-extraction lookup to enter the immutable model
pack's fixed `Record-Parakeet-v3-aed0274` distribution wrapper before invoking
the same allowlisted installer. Record 1.3.1 verified and expanded the archive
but could not discover the nested model folder through the automatic path.

CI keeps general product source and the main-app entitlements network-denied,
audits the helper source separately, rejects configurable remote URLs and raw
network/tool paths, verifies the helper's exact entitlement set, and inspects
both signed components after packaging.

## Consequences

- First-run Parakeet setup becomes one explicit action in Settings while
  recording remains usable if setup is skipped or fails.
- GitHub receives ordinary connection metadata for the model request but no
  captured content or local application data.
- The roughly 466 MB model remains outside Git, the app bundle, DMG, and
  routine Sparkle update archive.
- Updating the model URL, size, hash, files, allowed hosts, or helper
  entitlement set requires code review, deterministic tests, and a new ADR or
  amendment.
