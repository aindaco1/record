# ADR 0023: Preserve literal and meaningful repeated speech

Accepted for local implementation on September 23, 2026. No release is implied.
Amends model selection and candidate policy in
[ADR 0010](0010-on-device-transcript-refinement.md).

## Context

The fixed native/Jev examples showed an opening filler left intact and an
intentional repeated word removed. A model-only switch improved fillers but
lost quoted words. A separately frozen 20-case corpus reproduced loss of
grammar, quotation, sentence boundaries and emphatic repetition. A model
instruction alone is not a preservation boundary.

## Decision

Use the general Apple model with the existing indexed schema, prompt,
512-token budget and bounded batches. Retain the shared Platform adapter and
all availability, cancellation, fallback and local-only behavior.

Strengthen RecordCore's deterministic policy before and after advice:

- Preserve segments containing quotation or code-literal markers, including
  unfinished quotations. Apostrophes inside words do not count as quotation.
- Consider repeated words only from a small English pronoun/article allowlist.
  Preserve other repetition, punctuation boundaries and runs of three or more.
  Eligible pairs still require advice; inclusion does not prove a stutter.
- Revalidate source token, kind and eligibility during application, so a stale
  plan or remove decision cannot bypass these restrictions.
- Keep overlap, numeric-token, unknown/duplicate decision and whole-utterance
  preservation checks. Do not accept rewritten text from the model.

Record this as `candidate-removal-and-overlap-v2`. The report schema remains v1;
its fields and raw-source hash contract are unchanged. Existing sessions require
no migration and are never reprocessed implicitly.

## Consequences and validation

The original 11-case corpus, Jev questions, threshold and controls remain frozen.
The new regression suite is separately pinned and uses the same evaluator and
synthetic-only transport. Judge-control mismatches remain failures regardless
of product improvements.

The policy intentionally leaves extra filler/stutters in quoted segments and
preserves uncertain repetition. It identifies markers within each segment;
it does not infer quoted intent or resolve quotation across multiple segments.
Evidence is English and does not establish general accuracy across languages
or hardware. Capture and release gates retain their authority.

See [the cleanup evaluation](../testing/cleanup-fix-2026-09-23.md) for results and
[the testing guide](../testing/jev.md) for commands.
