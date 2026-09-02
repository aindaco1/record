# Quill issue and pull-request migration

This ledger records every Quill issue and PR reviewed on 2026-08-06. Source
items remain untouched because Record is a standalone repository and the
Record owner does not have write access to `digimata/quill`.

This is a historical migration record, not the current roadmap. Later shipped
behavior and scope decisions are documented in `CHANGELOG.md`, `ROADMAP.md`,
and the current Record issue-triage snapshot.

## Issues

| Source | Decision in Record |
|---|---|
| [#28 Name confusion](https://github.com/digimata/quill/issues/28) | Resolved by the new Record name; retain as provenance, no implementation issue. |
| [#23 selected-app audio](https://github.com/digimata/quill/issues/23) | Accept through ScreenCaptureKit application/window/display filters and persistent picker choices. |
| [#22 browser speaker names](https://github.com/digimata/quill/issues/22) | Defer until after v1; permit only local native messaging through the isolated plugin protocol. |
| [#19 transcription duplicates](https://github.com/digimata/quill/issues/19) | Accept with a fixture corpus and non-destructive duplicate annotations before automatic suppression. |
| [#15 invisible recording icon](https://github.com/digimata/quill/issues/15) | Accept using asset-catalog status variants plus light/dark/high-contrast snapshot tests. |
| [#14 duplicate segments/attribution](https://github.com/digimata/quill/issues/14) | Closed duplicate; cover under #19 regression tests. |
| [#13 translate to English](https://github.com/digimata/quill/issues/13) | Defer to an optional local Whisper translation engine; never a service call. |
| [#11 visible recording failures](https://github.com/digimata/quill/issues/11) | Accept as explicit healthy/degraded/failed UI states driven by capture health events. |
| [#8 crash recovery](https://github.com/digimata/quill/issues/8) | Accept; atomic `session.json` begins this work and segmented video completes it. |
| [#5 Whisper/VAD](https://github.com/digimata/quill/issues/5) | Accept a local Whisper engine after model import, cancellation, long-audio, and VAD regression tests exist. |

## Pull requests

| Source | Decision in Record |
|---|---|
| [#55 Parakeet v3](https://github.com/digimata/quill/pull/55) | Superseded by #4 and Record's typed model registry. |
| [#54 LaunchAgent audio](https://github.com/digimata/quill/pull/54) | Preserve diagnostic insight; replace LaunchAgent deployment with a signed app bundle and SMAppService. |
| [#53 releases/Homebrew](https://github.com/digimata/quill/pull/53) | Reuse the signed/notarized app, protected release environment, and attestation outcomes. A Homebrew Cask was later declined for the 1.x scope. |
| [#52 Whisper](https://github.com/digimata/quill/pull/52) | Reimplement behind the local engine protocol after cache, cancellation, VAD, and long-file tests. |
| [#27 meeting detection](https://github.com/digimata/quill/pull/27) | Defer; automatic prompts are outside the focused v1 workflow. |
| [#25 echo filter](https://github.com/digimata/quill/pull/25) | Rework against real fixtures; preserve canonical segments and make suppression reversible. |
| [#24 echo filter duplicate](https://github.com/digimata/quill/pull/24) | Superseded by #25. |
| [#21 MIT license](https://github.com/digimata/quill/pull/21) | Already present upstream; no port needed. |
| [#20 diarization](https://github.com/digimata/quill/pull/20) | Defer full model integration; retain typed speaker attribution and evaluate locally through Podman-compatible fixtures. |
| [#18 races and icon](https://github.com/digimata/quill/pull/18) | Reimplement with actor/queue ownership and asset tests; do not port incomplete locking. |
| [#17 race fix duplicate](https://github.com/digimata/quill/pull/17) | Superseded by #18. |
| [#16 race fix duplicate](https://github.com/digimata/quill/pull/16) | Superseded by #18. |
| [#12 signed DMG](https://github.com/digimata/quill/pull/12) | Accept release goal; replace hard-coded identity and permissive validation with protected secrets and strict verification. |
| [#10 Windows fixes](https://github.com/digimata/quill/pull/10) | Reject as out of scope for an Apple-Silicon-only macOS product. |
| [#9 language-selected model](https://github.com/digimata/quill/pull/9) | Rework: engine, model, and language are separate typed choices. |
| [#7 completion marker](https://github.com/digimata/quill/pull/7) | Accept and generalize through atomic session/transcript state. |
| [#6 track watchdog](https://github.com/digimata/quill/pull/6) | Rework using callback heartbeats, write results, queue depth, and signal meters; file growth alone misses digital silence. |
| [#4 configurable Parakeet](https://github.com/digimata/quill/pull/4) | Accept concept; Record defaults to v3 while retaining explicit v2 compatibility. |
| [#3 AssemblyAI](https://github.com/digimata/quill/pull/3) | Reject: cloud audio upload and API-key handling violate ADR 0002. |
| [#2 mic restart](https://github.com/digimata/quill/pull/2) | Reimplement as a synchronized capture-state transition with device-change and A/V continuity tests. |
| [#1 Parrot link](https://github.com/digimata/quill/pull/1) | Already merged in inherited history. |

Substantive source code copied in the future must retain its license notice and
appropriate author attribution. Source links alone do not authorize copying
code with an incompatible license.
