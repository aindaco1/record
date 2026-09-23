# Apple adviser comparison — September 23, 2026

This records the initial model/schema/context experiments. The subsequent
[cleanup fix](cleanup-fix-2026-09-23.md) adds deterministic preservation checks;
its results supersede the production-default decision recorded here.

The CutNotes-inspired experiments do not justify changing Record's production
adviser yet. Switching to the general model improves filler removal but loses
quoted speech; none of these variants preserves the intentional repeated
“very” in the emphasis case. The production default remains content tagging.
No release, app installation or version bump was performed.

## Method

All four runs use the same 11 reviewed synthetic cases, 22 paired controls,
35 Jev questions, 0.10 margin, shared evaluator pin and whole-token removal
pipeline. Every generated result passes through the real echo suppressor,
refinement coordinator and deterministic application policy. Only allowlisted
synthetic source/candidate text reaches Jev. No private audio or transcript is
used. Fixtures and judgment thresholds were not revised after seeing results.

The first comparison changes only Apple's model use case. The Boolean and
sentence-context experiments are each compared with that general-model run:

| Variant | Model | Response | Context | Jev native passes |
| --- | --- | --- | --- | --- |
| Baseline | Content tagging | Indexed keep/remove array | Six words per side | 9/11 |
| General | General | Same indexed array | Same six words | 9/11 |
| General + Boolean | General | One removal Boolean per candidate | Same six words | 8/11 |
| General + sentence | General | Same indexed array | Enclosing English sentence, at most 200 characters per side | 9/11 |

Instructions, prompt template and the 512-token response limit remain fixed.
The Boolean experiment changes the guided schema and handles candidates
individually; these results do not isolate schema effects from batching on
longer inputs. Sentence expansion remains inside each source segment and cannot
alter candidate identity, removal eligibility, speaker, or timing.

All variants complete native inference and pass 11/11 structural checks.
Every run retains the same existing judge-control false failure: 21/22 controls
match their engineering labels, with no false passes. Each combined result
therefore remains false and the runner exits 1.

## Observed tradeoffs

- Baseline keeps the disposable opening “Um,” and drops the repeated “very”.
- General removes the opening filler, but also removes the explicitly quoted
  word “um” from `The exact word in the caption is “um” and must stay.` It still
  drops the repeated “very”. Those preservation failures rule out adopting the
  model switch on these results.
- The tested Boolean configuration preserves the quoted filler but retains
  both the disposable opening filler and accidental repeated “I”; it also
  drops the intentional repeated “very”. Simpler output alone is not a fix.
- Sentence context produces identical output to the general variant for all
  11 cases. This short corpus does not establish its value for long passages.

Outputs were inspected directly alongside Jev's findings. This is a bounded
development comparison, not a claim about general model accuracy, unseen
transcripts, other languages, different Apple model versions, or release
acceptance. It does not make the existing production cleanup failures acceptable.

## Model evidence

Native and local Jev reports now record the selected experiment, use case and
OS version, together with passive model metadata when Apple exposes it:

- macOS 27.0, build `26A428`, on Apple M1 Max.
- Model display name: `AFM 3 Core` for both use cases.
- Context size: 4096.
- Reported capabilities: guided generation, tool calling, vision.

Use case is recorded separately because model display name alone does not
distinguish these configurations. Older operating systems may not expose this
metadata; missing information remains absent. These fields stay local and are
excluded from Jev payloads.

Local `.build/jev/` evidence directories retain source/corpus hashes, native
output, controls, raw probabilities and full reports:

- Baseline: `2026-09-23T16-07-31-161Z-672f6cbf`.
- General: `2026-09-23T16-08-01-558Z-d4b87f4c`.
- Boolean: `2026-09-23T16-08-31-546Z-e524a43e`.
- Sentence: `2026-09-23T16-09-00-805Z-86c78f08`.
- Final production check: `2026-09-23T16-14-13-408Z-df04dbf4`.

## Engineering validation

The full `scripts/ci/validate.sh --full` passes on the final implementation:
347 Swift tests with two expected skips and zero failures, 13 offline evaluator
tests, source/security contracts, documentation checks and the arm64 release
build. Focused tests cover bounded sentence context, stable candidate identity,
unchanged whole-token application, empty-input inference avoidance, explicit
experiment selection and exclusion of model metadata from outgoing text.

The final normal production run reproduces the baseline's 9/11 Jev candidate
passes and 21/22 correct controls, with identical native case results. It exits
1 as intended for those existing quality findings. Build/test success does not
override that outcome. Capture hardware, notarization, installed-app acceptance
and broader formatting quality were not exercised by this comparison.

## Decision for the next release

Retain whole-token removal, source preservation, cancellation, unavailable-model
fallback and existing production defaults. Keep the comparison harness and
metadata in development testing. Future adviser changes must improve cleanup
without losing quotation, emphasis or meaning on fixed comparisons and broader
representative cases before promotion. Keep the judge-control mismatch visible.

Apple recommends its general use case for classifications outside the content
tagger's specialized categories. That makes it a reasonable experiment, not a
guarantee of safer cleanup. See
[Apple's content-tagging guidance](https://developer.apple.com/documentation/foundationmodels/categorizing-and-organizing-data-with-content-tags).
Changing to permissive transformation guardrails is not part of this experiment:
Apple says structured responses retain default guardrail behavior. See
[permissiveContentTransformations](https://developer.apple.com/documentation/foundationmodels/systemlanguagemodel/guardrails/permissivecontenttransformations).

The [developer guide](jev.md#apple-adviser-comparisons) documents reproducible
commands; the [release runbook](../runbooks/release.md#candidate-preparation)
records how these findings inform the next candidate. Deploying the shared
native implementation requires each affected app to be rebuilt and released,
but those releases can be independent and combined with other planned changes.
Testing-only improvements require no installed-app update.
