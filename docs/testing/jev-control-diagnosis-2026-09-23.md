# Jev control diagnosis — September 23, 2026

The [1.4.5 release evidence](1.4.5-release.md) contains 11/11 original and 20/20
regression product passes, but only 21/22 and 36/40 correct judge controls.
These control findings concern Jev's assessment of fixed, deliberately good/bad
examples. They are not five defects in Record's generated output.

## What failed

| Control | Expected | Observed | Diagnosis |
| --- | --- | --- | --- |
| `overlapping-disagreement-control-pass` | Pass | Fail | The candidate retains `me: No, I I need another day.` The requirement says “local speaker” without defining its relationship to `me`. The engineering label is reasonable, but the question could be more explicit. |
| `grammatical-that-control-fail` | Fail | Pass | `I know that answer is correct.` omits one of the required two instances of `that`. Semantic similarity cannot satisfy the literal-preservation requirement. |
| `repetition-run-control-fail` | Fail | Pass | `All I hear is I I.` has only two final instances of `I`; the requirement demands three. This is an exact count, not a semantic judgment. |
| `grammatical-had-control-fail` | Fail | Review | `She had enough by Thursday.` omits the second `had`. Fail led pass by only 0.03, below the unchanged 0.10 margin. |
| `quoted-span-control-fail` | Fail | Review | `She said “we should wait” before leaving.` changes the required exact quotation. Pass led fail by only 0.01. |

The reviews are abstentions, not accepted bad outputs. The two confident false
passes demonstrate a limit of this judge for literal preservation. The baseline
false failure may also involve question ambiguity; the API provides choices and
probabilities, not an explanation establishing the cause. No new inference is
needed to see that the candidate omits required words.

The earlier [cleanup report](cleanup-fix-2026-09-23.md) recorded 37/40 correct
regression controls. The later release run changed the `grammatical-had` result
to review, producing 36/40. This variation is another reason not to rerun until
green or lower the probability margin. The original Jev investigation did expose
real filler/emphasis defects; those product changes are documented separately.

## Testing changes

- Report product results separately from judge-control accuracy, with explicit
  blocking reasons and expected/observed decisions for each flagged example.
- Require every question to have a recognized answer before a case can pass.
- Test the four literal-loss scenarios against the exact/native checker while
  simulating passing Jev judgments. They remain blocked. The quoted control also
  moves a quote onto a different token and is rejected by source preflight; a
  token-only quotation loss is separately rejected by preservation checks.
- Keep corpus hashes, labels, questions, shared evaluator, model allowlist,
  margin, budgets and exit codes unchanged. Both historical runs still fail the
  combined gate; the new report explains why.

These changes improve diagnosis and verify existing safeguards. They do not
claim improved Jev accuracy. The offline adapter regressions use the observed
decision patterns; the saved full reports were also replayed without network
calls, preserving their distributions and original evidence.

Validation passed: all 17 offline adapter tests and `./scripts/ci/validate.sh`,
including documentation/source contracts, Swift tests and the arm64 production
build. No new native inference or hosted judgment was needed for these changes.

## Future calibration

Use exact code assertions for token counts, literal quotations, identifiers,
speaker/time metadata and echo retention. Reserve semantic evaluation for
meaning, negation, attribution, omissions and emphasis that exact checks cannot
resolve. Current frozen controls remain useful as a record of judge limitations.

A separately versioned comparison could replace “local speaker” with “speaker
labeled me” and distinguish literal preservation from semantic fidelity in the
rubric. Freeze that variant before inference and assess it on fresh independently
reviewed synthetic holdouts as well as existing controls. Do not relabel or remove
the difficult controls to claim an improvement. Passing these 31 engineering
examples does not establish real-recording or general-language accuracy.

This is developer testing only: no app behavior, package version, release,
installation, user recording or hosted evaluation changed.
