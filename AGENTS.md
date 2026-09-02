# Repository instructions

These instructions apply to all automated contributors working in this
repository.

## Product invariants

- Keep screenshots, recording content, transcripts, clipboard content and
  clipboard-derived names, diagnostics, and session metadata local.
- Do not add accounts, analytics, upload clients, cloud transcription, or model
  downloads.
- The main app must retain no incoming or outgoing network entitlement. The
  reviewed Sparkle downloader XPC service is the only update network path.
- Never invoke configured completion hooks through a shell. Require absolute
  executable paths and pass arguments directly.
- Preserve raw media until a complete exported session has been validated.
- Keep microphone and system audio as separate source files.

## Architecture

- Put reusable state and policy in `RecordCore`.
- Keep AppKit, ScreenCaptureKit, AVFoundation, ServiceManagement, Sparkle, and
  other system APIs behind narrow adapters.
- Make state transitions explicit and deterministic before wiring UI effects.
- Prefer Apple frameworks and small local types over new dependencies.
- Keep capture callbacks nonblocking and use bounded queues.

## Changes

- Add a deterministic regression test for every bug fix when the behavior can
  run without TCC or recording hardware.
- Do not weaken local-only, entitlement, path-containment, or signature guards.
- Never commit recordings, transcripts, models, credentials, certificates,
  signing keys, security bookmarks, or absolute personal paths.
- Regenerate the app icon only with `scripts/release/generate-icon.sh`; keep
  `Sources/Record/Resources/AppIcon.svg` as the canonical source.
- Update `CHANGELOG.md`, user documentation, and an ADR when a change alters a
  durable privacy or architecture decision.

## Validation

Run the smallest relevant test while iterating, then:

```sh
./scripts/ci/validate.sh
```

Before a release or high-risk capture/signing change, also run:

```sh
./scripts/ci/local-gate.sh
```

Complete the applicable manual rows in `docs/testing.md`; never claim hardware
behavior that was not actually exercised.

## Releases

- Release only from `main` using a new signed annotated
  `vMAJOR.MINOR.PATCH` tag.
- Never move or delete an existing release tag.
- Keep release secrets in the protected `release` environment and never print
  them.
- Follow `docs/runbooks/release.md` and verify notarization, checksums, update
  signatures, and downloaded assets after publication.
