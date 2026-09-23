# Transcript cleanup fixes — September 23, 2026

Record's local implementation now removes the opening filler flagged by Jev
while preserving the intentional repetition it previously lost. This follows
the [initial model comparisons](apple-adviser-2026-09-23.md), which established
that changing the model alone also introduced quotation loss.

## Change

Use Apple's general model with the existing indexed response, prompt, six-word
contexts and 512-token budget. Before asking the adviser, RecordCore preserves
segments containing quotation/code markers and limits repeated-word candidates
to short pronoun/article pairs. Other repetitions, punctuation boundaries,
longer runs and overlap remain protected. Application rechecks eligibility so
an unsafe model decision or stale plan cannot bypass the policy.

The adviser still approves eligible candidates; no generated replacement text
is accepted. Raw transcripts, speaker labels, timestamps and source media keep
their existing preservation contract. The policy becomes
`candidate-removal-and-overlap-v2`, with no report-schema or session migration.
See [ADR 0023](../adr/0023-conservative-cleanup-preservation.md).

## Before and after

These counts require both exact/native checks and Jev's product judgments.
Judge controls are reported separately and prevent an overall pass below.

| Corpus and configuration | Passing product cases | Passing exact/native checks |
| --- | --- | --- |
| Original 11, original content-tagging/v1 policy | 9/11 | 11/11 |
| Original 11, content-tagging/v2 preservation rules | 10/11 | 11/11 |
| Original 11, general/v2 production fix | 11/11 | 11/11 |
| Additional 20, original content-tagging/v1 policy | 6/20 | 9/20 |
| Additional 20, general/v2 production fix | 20/20 | 20/20 |

Testing the preservation rules separately fixed emphasis loss while leaving
the opening filler. Selecting the general model then fixed that remaining
case. The additional suite covers fillers, stutters, emphasis, refusals,
grammatical repetition, sentence boundaries, quotation, code literals,
contractions, longer runs, numbers and overlap.

The original 11-case corpus and all its questions, thresholds and labels remain
unchanged. The additional 20 synthetic cases were written and hash-pinned
before evaluating either implementation against them. They use the same
evaluator with 40 paired controls. This is bounded engineering evidence, not
an independent accuracy benchmark or proof across languages.

## Remaining evaluator findings

Every completed command still exits 1, deliberately:

- Original controls: 21/22 correct. Jev rejects the labeled passing
  `overlapping-disagreement-control-pass` despite its retained disagreement.
- Additional controls: 37/40 correct. Jev incorrectly accepts
  `grammatical-that-control-fail` and `repetition-run-control-fail`, which omit
  required repeated tokens. `quoted-span-control-fail` receives a review result
  rather than the expected failure.

The control results are the same before and after the product fix. They expose
judge limitations; changing product output cannot repair those fixed examples.
No labels, questions, probability margins or failure gates were relaxed. Exact
preservation checks on the product outputs remain authoritative even when Jev
would miss a token loss.

## Evidence and reproduction

All runs used macOS 27.0 build 26A428, AFM 3 Core, a 4,096-token model context,
and the same Platform revision. Model capabilities and source hashes are in
local evidence; only reviewed synthetic text and rubric questions went to Jev.

Run both suites after changing adviser or removal policy:

```sh
node scripts/test.mjs --quality-only
node scripts/test.mjs --quality-only --suite=regressions
```

The [testing guide](jev.md) explains setup, budgets, strict fixture selection
and the separate offline/full gates. Run folders under ignored `.build/jev/`:

| Run | Local folder |
| --- | --- |
| Original 11, before | `2026-09-23T16-14-13-408Z-df04dbf4` |
| Additional 20, before | `2026-09-23T16-53-20-411Z-4cffde55` |
| Preservation rules with content-tagging | `2026-09-23T16-57-35-354Z-06149f88` |
| Original 11, production fix | `2026-09-23T16-58-04-160Z-697ecd74` |
| Additional 20, production fix | `2026-09-23T16-58-28-429Z-d0d4b404` |

`./scripts/ci/validate.sh --full` passed for this implementation: 351 Swift
tests with zero failures and two expected skips, all 14 offline Jev-adapter
tests, the source/privacy contract gates, documentation checks and the arm64
release-configuration build. The skips cover the explicitly invoked native
quality probe and the external multitrack-media fixture. The native quality probe was
exercised separately in the runs above.

The policy intentionally retains extra fillers in quoted segments and uncertain
repetition. It detects quotation markers within each segment, not quoted intent
or quotation spanning multiple segments. The repeat allowlist is English.
These tests do not establish capture, ASR or hardware accuracy. No release,
version bump, installed-app replacement or physical recording acceptance was
performed for this change.
