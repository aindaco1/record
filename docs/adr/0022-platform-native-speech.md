# ADR 0022: Platform-owned native speech

Accepted for implementation on 2026-09-23. No release or model upgrade.

## Decision

Adopt the native SwiftPM package from the pinned `shared/dust-wave-platform`
submodule. Platform owns local speech/model verification and Apple session,
generation-budget, cancellation, and SDK compatibility mechanics. RecordSpeech
re-exports the implementation and RecordCore aliases the existing model ID type,
preserving library and serialized configuration contracts.

Record retains capture, separate source media, transcript cleanup candidates,
prompts, guided schema, batch size, acceptance checks, model import/download UX,
and all UI/storage policy. FluidAudio stays exactly 0.15.7. Neither app network
entitlements nor update/model download exceptions change. The local-only source
guard also scans the shared native source; offline ModelHub enforcement remains
covered by runtime tests. Hosted Jev receives only the existing pinned synthetic
corpus under ADR 0021.

## Validation and rollback

Run `git submodule update --init --recursive`, then `node scripts/test.mjs`.
The shared package has its own tests; they do not replace Record's full local
validation or per-case native/Jev comparison with the pre-migration baseline.
Preserve existing failing or review cases and fixed judge thresholds in reports.

Revert the Platform gitlink, package/lockfile, compatibility adapters and build
changes together. Restore the previous RecordSpeech implementation from the
parent commit. No session data or model cache is migrated. Consumer app releases
remain independently signed and reversible.
