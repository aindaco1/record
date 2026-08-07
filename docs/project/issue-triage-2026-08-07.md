# GitHub issue triage — 2026-08-07

All open issues were reviewed against the 1.0.0 source, tests, release
artifacts, and the 1.0.1 candidate. None were stale by age: every issue had
been updated on August 6 or 7. The useful distinction is completed, maintenance,
next feature release, or later.

GitHub labels are the source of truth for scheduling:

- `target:maintenance` — distribution or patch follow-up;
- `target:next` — planned for the next feature release;
- `target:later` — valid work outside the next release.

| Issue | Disposition | Evidence or remaining scope |
|---|---|---|
| #29 Recording names and Gifski | Closed as completed | Templates, safe clipboard access, collisions, local app handoff, and tests shipped in 1.0.0. |
| #28 Capture privacy plugins | Next | Capture-only filters shipped; supported Focus/notification-sound workflow and its recovery UX remain. |
| #27 Menu workflow and history | Next | Menu capture ships; source UI, pause/resume, history, shortcuts, and accessibility remain. |
| #26 Pause/resume | Next | Requires crash-safe segmented pause/resume and hardware acceptance. |
| #25 Transcript deduplication | Next | Reversible cross-track overlap detection remains unimplemented. |
| #24 Parakeet import/selection | Next | 1.0.1 adds verified v3 import; first-class v2 selection/import and typed metadata remain. |
| #23 App lifecycle | Maintenance | 1.0.1 removes LaunchAgent code and fixes login registration; close after upgrade/TCC smoke testing. |
| #22 No-network boundary | Closed as completed | Main app remains network-denied; offline model enforcement and verified local import are tested; Sparkle XPC is documented separately. |
| #21 Browser metadata bridge | Later | Optional local bridge is not required for core capture. |
| #20 Native status assets | Next | Idle/recording presentation ships; paused/degraded/failed states and appearance matrix remain. |
| #19 Native editor | Later | Non-destructive edit model and native export UI remain a larger product slice. |
| #17 Release/Homebrew | Maintenance | Signed notarized GitHub release ships; Homebrew Cask and clean-machine uninstall verification remain. |
| #16 Cursor/click rendering | Later | Needs cross-display scale testing and rendering policy. |
| #14 Performance harness | Next | Automated logic gates exist; dedicated Apple Silicon hardware metrics remain. |
| #13 Whisper/translation | Later | Optional MacWhisper integration ships; cancellation, translation, VAD, and resource budgets remain. |
| #12 Out-of-process plugin host | Later | Built-in capability-specific plugins ship; general extension protocol remains intentionally deferred. |
| #10 A/V/camera synchronization | Later | Screen/system/mic share a timeline; camera and one-hour drift acceptance remain. |
| #9 Source picker | Next | Capture filter foundations ship; user-facing display/window/app/region selection remains. |
| #6 Microphone route recovery | Next | Route-change restart and discontinuity reporting need hardware tests. |
| #5 Capture concurrency | Next | Bounded queues ship; route churn, health events, and hardware failure surfacing remain. |
| #4 Bounded 4K60 pipeline | Next | Bounded pipeline ships; pause/recovery and sustained 4K60 hardware evidence remain. |
| #2 Interrupted recovery | Next | Deterministic recovery ships; invalid-tail quarantine, at-most-once hooks, and forced-phase coverage remain. |

This audit avoids closing umbrella issues just because one slice shipped. An
issue closes only when its remaining acceptance criteria are either completed
or explicitly replaced by a documented product decision.
