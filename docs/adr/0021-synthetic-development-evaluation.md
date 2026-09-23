# ADR 0021: Synthetic transcript evaluation in development

## Context

Record's deterministic tests enforce bounded token removal, echo policy,
speaker/time preservation and safe fallback. Those contracts cannot establish
that the Apple adviser preserves emphasis or quoted hesitation in real model
output. CutNotes combines deterministic checks with Jev semantic review; Dust
Wave Platform now provides reusable Jev transport and response validation.

## Decision

Make `node scripts/test.mjs` the standard local development command, combining
the existing gate, a native synthetic cleanup probe, and hosted Jev review.
Require an explicit `--offline` option to omit inference. Keep hosted CI and
release validation independent of external model availability and credentials.

Reuse Record's existing echo suppressor, refinement coordinator and Apple adviser
without changing their implementations. Reuse a hash-verified, revision-pinned
external development checkout of Platform Test Core for Jev questions, bounded
Cloudflare transport and judgment validation. Keep Record's adapter responsible
for synthetic fixtures, atomic requirements, provenance, spending and reporting.

Only reviewed hand-authored synthetic text may be sent. Validate the entire
corpus before authentication and reconstruct outgoing output from its allowed
tokens and metadata. Provide no custom-input or private-session evaluation path.
Product targets, entitlements, runtime dependencies, source media and user data
handling remain unchanged. The developer evaluator is not shipped in the app.

Require review for near ties or unrecognized models. Combined results must also
pass exact/native checks and paired judge controls. Treat the initial margin as
provisional; controls do not prove independent calibration or general accuracy.

## Consequences

- Local developers need Node, the pinned shared checkout, an eligible Apple
  model and Cloudflare credentials for the complete development workflow.
- Missing capabilities and incomplete responses cannot silently pass. Explicit
  offline and request-preview modes state what was omitted.
- Jev requests add a small bounded estimate of inference cost to local testing.
  There are no automatic retries, downloads, purchases or top-ups.
- Native and remote evidence stays in ignored local build storage. Captured or
  user-derived recordings/transcripts must never become committed fixtures.
- Existing capture, ASR, recovery, signing and manual hardware gates retain
  their authority. This tooling change requires no app version or release.

The [developer testing guide](../testing/jev.md) defines setup, limits and evidence.

## Apple comparison extension — September 23, 2026

This records the initial comparison. The subsequent production model and
preservation-policy change is documented in
[ADR 0023](0023-conservative-cleanup-preservation.md).

The same runner supports explicit, allowlisted model/schema/context experiments
on the same reviewed corpus. At this stage production used the content-tagging
adviser; alternative Boolean and sentence-context adapters exist only in tests.
Model selection is an internal injection point, not a user setting or an
environment-controlled product path. Both availability and generation use the
same selected profile.

Capture passive Apple model identity, context size, capabilities and OS version
in local evidence. The evaluator reconstructs only the same allowlisted
synthetic text for remote requests; experiment metadata never leaves the Mac.
Controls, questions, thresholds and the pinned shared evaluator remain unchanged.
Results that regress quotation, emphasis or meaning are not promoted to the
production default, even if they remove more fillers. See the
[dated comparison](../testing/apple-adviser-2026-09-23.md).
