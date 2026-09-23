# Shared native migration — September 23, 2026

Record, CutNotes, Auto Subtitle and Podcast Visualizer now consume the same
Platform Swift package, pinned at
`0affb6c5652611b87947bd87762d8aa17d35ea32`. It owns local speech primitives and
Apple generation mechanics. Product prompts, schemas, cleanup/presentation
policies, storage, permissions and release authority remain in each app.
See [ADR 0022](../adr/0022-platform-native-speech.md) and the
[shared package guide](../../shared/dust-wave-platform/native/README.md).

## Comparison method

The baseline included the existing development changes in Record and Podcast
Visualizer. Fixed synthetic corpora, questions, thresholds, model profiles,
response budgets and exact FluidAudio versions were preserved during extraction.
Both sides ran on the same Apple M1 Max with macOS 27 and Xcode 27. Only the
allowlisted synthetic text and its generated candidates reached hosted Jev.

| App | Native output comparison | Before and after quality outcome |
| --- | --- | --- |
| Record | 11/11 identical | Exact checks 11/11; Jev candidates 9/11; controls 21/22 |
| CutNotes | 16/16 identical | Exact checks 15/16; combined checks 11/16 |
| Auto Subtitle | 13/13 identical | Deterministic checks pass; semantic review remains required |
| Podcast Visualizer | Two paired runs per implementation | Both old and new produced one run with 17 passes and one with 16 passes plus one review; no deterministic failures; controls 14/14 throughout |

Podcast Visualizer's same caption chapter alternated between “Caption readability
improvements” and “Caption formatting consistency” in both implementations.
The latter remained flagged for review. All four runs were retained; a later
passing run does not erase the earlier review outcome.

No extraction-specific regression was observed in this bounded comparison.
This is not a claim that every formatter passes its quality bar. Record's
existing filled-pause/emphasis failures and judge-control mismatch, CutNotes'
existing failures, and the subtitle/chapter review cases remain visible.
The [original Record evaluation](jev-2026-09-23.md) describes its cleanup issues.
No corpus, label or threshold was changed to obtain a passing result.

A separate local synthetic-audio probe produced identical old/new transcription
JSON through Auto Subtitle and CutNotes, including confidence and word timings.
It used existing verified model assets and generated speech, with no microphone,
private recording, or model download.

## Engineering validation

- Platform: all 11 native tests pass independently with FluidAudio 0.15.5, 0.15.6
  and 0.15.7; Node tests, secret scan, shell and workflow checks pass. All four
  consumer gitlinks and speech lockfile revisions pass the cohort check.
  [Hosted CI](https://github.com/aindaco1/dust-wave-platform/actions/runs/35884857833)
  also passes all six jobs: the three native versions on macOS 26, Node 22/24,
  and the Jekyll recipe.
- Record: full validation and local gate pass, including Swift tests,
  ThreadSanitizer, AddressSanitizer, arm64 builds, local packaging, checksums,
  disposable update signatures and unchanged entitlement restrictions. The
  local-only source guard now also scans shared native sources.
- CutNotes: 175 Python and 23 Swift tests pass; the full debug app bundle builds
  and passes ad-hoc code-signature verification.
- Auto Subtitle: Node and 29 Python tests pass; both Swift helpers build; the
  full app build verifies bundle layout, local imports and Mach-O dependencies.
- Podcast Visualizer: 216 Node tests pass with three expected skips; Swift app
  and sidecar tests plus arm64 release compilation pass. Old and new provenance
  schemas retain strict field, hash and signing-metadata validation.

Local comparison reports retain per-case outputs, source/corpus hashes, judge
probabilities and inference metadata. Generated media, credentials and build
artifacts are excluded from repository changes. Consumer hosted CI, physical capture,
other hardware/OS versions, notarization and installed-app acceptance were not
established by these checks.

## Future improvements

Change the common implementation once in Platform, run its native matrix, then
advance the four consumer pins together and repeat their fixed native/Jev
comparisons. Run `node scripts/check-native-consumers.mjs --root /path/to/projects`
from Platform to detect pin or speech dependency drift. Each app retains its
own acceptance and rollback decision. Installed apps receive changes through
their normal signed updates; this migration does not publish any release,
change an app version, or install an app.
