# Transcript cleanup development tests

Run the standard local development suite from a local APFS checkout:

```sh
node scripts/test.mjs
```

It runs the existing full deterministic validation, then exercises Record's
actual echo suppressor and `TranscriptionCoordinator.refinementPass` with the
on-device Apple adviser. Finally, hosted Jev reviews the synthetic results and
paired controls. No capture permission, recording, ASR model, MacWhisper, app
installation or release is involved.

## Setup

Use the normal Xcode 27 environment, Node 20.9 or newer, and a Mac with Apple
Intelligence ready for English. An unavailable or failed Apple adviser is a
failed quality check, even when its safe fallback produces a readable result.

The shared evaluator is `@dustwave/test-core` 0.3.0 from
[Dust Wave Platform](https://github.com/aindaco1/dust-wave-platform), the same
implementation used by Pool. The default source is the pinned
`shared/dust-wave-platform` submodule at
`0affb6c5652611b87947bd87762d8aa17d35ea32`. The adapter checks that revision
and the hashes of all three imported source files before using it. It does not
download or install dependencies. No JavaScript package enters Record's Swift
package or app bundle. CutNotes supplies the workflow pattern; Record does not
import its application-specific evaluator or change its frozen policy.

Initialize the pinned dependency:

```sh
git submodule update --init --recursive
```

Set `CLOUDFLARE_ACCOUNT_ID` and `CLOUDFLARE_API_TOKEN` in the local environment.
With no token, the adapter uses an existing cached Wrangler 4.136.2 login via
`npx --no-install`; it never installs Wrangler or prints credential output.
Alternatively, store only the account ID in the ignored
`.record-development.json`:

```json
{
  "cloudflare_account_id": "YOUR_ACCOUNT_ID"
}
```

Tokens must not be saved there or in evidence. Missing setup or credentials is
an error, never a silent offline pass. Each checkout has its own local config.
The runner removes Cloudflare credentials from validation/native child-process
environments; only the developer evaluator uses them.

An explicit `RECORD_TEST_CORE_ROOT` or `test_core_root` config override must be
an absolute checkout at that same reviewed revision and source hashes.

## Faster and explicit modes

```sh
# Existing deterministic gate only; no Apple or Jev inference.
node scripts/test.mjs --offline

# Native synthetic cleanup and Jev, omitting the general validation gate.
node scripts/test.mjs --quality-only

# Native cleanup and request preview; zero Jev authentication or requests.
node scripts/test.mjs --quality-only --dry-run

# Fast offline regression tests for this adapter.
node --test scripts/qa/jev.test.mjs
```

`scripts/ci/validate.sh`, hosted CI, sanitizers and release gates retain their
existing behavior and do not call hosted Jev or the Apple model. The source
contract gate also runs the offline Node adapter tests. Swift's explicit native
probe is skipped unless the development runner supplies its output destination.
The offline mode does not disable ordinary Swift dependency resolution.

## Apple adviser comparisons

The normal command always evaluates the app's production adviser. To compare
the lessons from CutNotes independently, use the same native/Jev workflow:

```sh
node scripts/test.mjs --quality-only --apple-variant=baseline
node scripts/test.mjs --quality-only --apple-variant=general
node scripts/test.mjs --quality-only --apple-variant=general-boolean
node scripts/test.mjs --quality-only --apple-variant=general-sentence
```

`baseline` selects the original content-tagging model and indexed response with
the current RecordCore removal policy; it does not reconstruct older binaries.
The policy version is recorded in native evidence.
`general` changes only the model use case. `general-boolean` uses a single
Boolean per candidate with the same prompt, instructions, six-word contexts
and 512-token budget. `general-sentence` keeps the indexed schema and replaces
the six-word windows with the enclosing English sentence, bounded to 200
characters on each side. Compare the last two with `general`, not with each
other. The Boolean and sentence implementations live only in the test target.
These flags never configure the installed app, and ambient experiment variables
cannot alter ordinary validation.

Keep the corpus, questions, thresholds and dependency pin frozen. Run every
variant against the same OS/model and retain failed results. Each invocation
uses the existing request/cost limits; it does not retry failed judgments.
Native evidence and the local Jev report now record the variant, use case and
OS version, plus the model name, context size and capabilities when macOS 27
exposes them. Metadata is passive, remains local, and is never part of a Jev
request. Missing older-OS model metadata is not inferred or fabricated.

See [the first comparison](apple-adviser-2026-09-23.md) before choosing a
configuration for the next Record release. Apple API guidance provides a
hypothesis; only observed preservation and cleanup results can justify adoption.

## Corpus and privacy boundary

### Regression suite

```sh
node scripts/test.mjs --quality-only --suite=regressions
```

This separately pinned set of 20 synthetic cases covers filler removal,
pronoun/article stutters, emphatic and grammatical repetition, sentence
boundaries, quotation marks, unfinished quotes, code literals, contractions,
longer repetition runs, numeric sequences and overlap. It was fixed before
evaluating the cleanup implementation and has 40 paired controls. Run it
alongside the original suite for adviser or removal-policy changes. The original
11 cases, questions and thresholds are unchanged, so historical comparisons
remain meaningful. Source paths come from an allowlist; there is no arbitrary
file or private-transcript input.

This suite reserves an estimated $0.088704 for its 66 questions under the same
rate/budget assumptions described below. Judge-control false passes, false
failures and review outcomes still prevent a combined pass. The
[cleanup report](cleanup-fix-2026-09-23.md) separates product improvement from
those evaluator limitations.

### Original comparison corpus

The [corpus](../../scripts/qa/fixtures/transcript-cleanup.json) contains 11
hand-authored English cases and 22 paired good/bad controls. It covers disposable
fillers, accidental repetitions, intentional emphasis, quoted hesitation,
negation, conditional approval, uncertainty, numbers, overlapping disagreement,
aligned echo, backchannels, and dialogue resembling instructions. These are
synthetic examples, not captured or user-derived transcripts.

There is no arbitrary transcript, session directory, saved-evidence or custom
fixture argument. The complete native run must match the reviewed corpus hash.
Before authentication, every outgoing candidate is reconstructed from the
fixture's tokens and speaker/time fields. Unknown text, rewritten or reordered
words, unknown segment metadata, duplicate cases and incomplete evidence stop
evaluation. Exact checks separately enforce expected echo retention and protected
speech. Only synthetic source/candidate text and rubric questions leave the Mac;
paths, native diagnostics, credentials, screenshots, recordings, clipboard data
and real session metadata are excluded.

Update the corpus hash in [the pin](../../scripts/qa/jev-pin.json) only after
reviewing new synthetic fixtures. Freeze corpus, questions, policy and shared
revision when comparing application changes. This is a developer boundary, not
a sandbox against a contributor deliberately rewriting the test tooling.

## Reading evidence

Each run creates a new ignored `.build/jev/<run>/` directory with `workflow.json`,
`native.json`, `corpus.json`, `report.json` and `review.md`. Partial runs remain
incomplete. Reports retain source/corpus hashes, raw answers, probabilities,
resolved model versions, usage, latency and flagged candidate text locally.

The 0.10 probability margin and recognized `jev-1.13.0` model are a provisional
starting policy, not a Record-calibrated accuracy claim. Controls use engineering
labels, not independent human ratings or an unseen validation set. Near ties,
uncertainty and unknown model versions require review. A false pass or false
failure on a control prevents a combined pass. Do not lower the threshold to
green a candidate; review surprising judgments against the original fixture.

Exit 0 means all stages passed, or the explicitly requested offline/preview
subset completed successfully. Exit 1 means completed native or semantic checks
need attention. Exit 2 means setup or evaluation was incomplete. Deterministic
validation failures stop the default workflow and retain their nonzero code.
Jev never overrides a native failure or an exact check. No result establishes
ASR accuracy, hardware capture, other languages, or release acceptance.

The shared transport rejects redirects, bounds requests/responses and timeouts,
stops at the first API error, and never retries or falls back. No purchases or
credit top-ups occur. The 35 questions reserve about $0.04704 at the
[TypeSafe input rate](https://docs.typesafe.ai/models) of $0.042 per million
tokens, checked September 23, 2026. This deliberately budgets 32,000 tokens per
question. The default estimate limit is $0.25; `--max-estimated-usd=...` may lower
it or raise it to at most $1. These are estimates, not a provider billing cap.
Gateway cache/logging request headers do not establish provider retention policy.

See [ADR 0021](../adr/0021-synthetic-development-evaluation.md) for the durable
boundary and [the testing matrix](../testing.md) for existing acceptance checks.
The [initial evaluation](jev-2026-09-23.md) records two cleanup findings and one
judge-control mismatch. The initial baseline therefore exited nonzero. The
follow-up cleanup changes improve product results, but unresolved judge controls
still prevent a combined pass; consult the dated reports for the diagnosis.
