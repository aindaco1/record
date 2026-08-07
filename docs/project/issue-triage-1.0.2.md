# GitHub issue triage for Record 1.0.2

All 21 issues open after Record 1.0.1 were reviewed against the shipped app,
tests, current product goals, and remaining acceptance criteria. None were stale
by age; the problem was scope. Many migrated umbrella issues described possible
future products rather than defects in the simple personal recorder that now
exists.

The 1.0.2 policy is:

- keep an issue open when it names a concrete reliability or distribution
  outcome we still intend to deliver;
- close completed umbrellas even when their original checklist imagined more;
- close speculative epics as not planned and preserve the useful idea in the
  ROADMAP;
- avoid duplicating a working external integration with a new in-process
  subsystem without evidence that the existing path is insufficient.

## Active after 1.0.2 triage

| Issue | Disposition | Remaining outcome |
|---|---|---|
| #2 Interrupted recovery | Keep | Validate/quarantine corrupt media tails and expand forced-termination coverage. 1.0.2 adds a safe recovery summary. |
| #5 Capture health | Keep | Surface per-track silence, write failure, route loss, and bounded-queue pressure without logging content. |
| #6 Microphone route recovery | Keep | Restart safely around real device-route changes and record timeline gaps. |
| #9 Source selection | Keep | Add user-facing display, app, window, and region choice when this becomes the next capture feature. |
| #17 Homebrew/clean install | Keep, narrowed | GitHub signing/notarization is complete; only optional Homebrew and clean install/uninstall acceptance remain. |
| #26 Pause/resume | Keep | Requires crash-safe segment rotation and real hardware acceptance. |
| #27 History/shortcuts | Keep, narrowed | 1.0.2 adds Open last recording; a larger history view and configurable shortcuts remain optional. |
| #40 GitHub SSH signing key | Keep | Account-level maintenance; it prevents future admin merge bypasses. |

## Closed or parked

| Issue | Resolution | Reason |
|---|---|---|
| #4 4K60 pipeline | Completed/overlap | Bounded queues, real-time HEVC, independent audio, atomic promotion, retries, and sanitizer tests ship. Remaining segmentation and health work belongs to #2, #5, and #26; long-run performance stays a release practice. |
| #10 Camera synchronization | Not planned | Screen, system audio, and microphone already share a timeline. Camera is a parked product idea, not a current defect. |
| #12 General plugin host | Not planned | Built-in capability-specific plugins are safer and sufficient; a third-party execution platform is disproportionate for personal use. |
| #13 First-party Whisper/translation | Not planned | The optional verified MacWhisper path covers local Whisper without duplicating model/runtime/VAD code in Record. |
| #14 Dedicated hardware harness | Not planned as a standalone project | Deterministic CI, sanitizers, package gates, and manual hardware checks remain; a permanent self-hosted lab is unnecessary today. |
| #16 Cursor/click effects | Parked | Useful polish, but cross-display input capture adds privacy and testing cost with no current need. |
| #19 Native editor/playback speed | Parked | A non-destructive editor is a separate product surface. Record should stay a reliable recorder first. |
| #20 Status assets | Completed | The NewKap ring, white recording treatment, Reduce Motion behavior, dimensions, color, and animation are tested. Future paused/degraded presentation belongs with the features that introduce those states. |
| #21 Browser metadata bridge | Not planned | Native messaging and an extension create a new metadata trust boundary for marginal personal value. |
| #23 App-bundle lifecycle | Completed | Record 1.0.1 is installed with stable TCC identity, SMAppService login, no LaunchAgent writer, signed updates, and tested lifecycle behavior. |
| #24 Parakeet v2/v3 importer | Completed with a simplifying decision | Verified, atomic v3 setup ships. v3 remains the sole first-class model until a real compatibility need justifies v2 UI and another pinned manifest. |
| #25 Transcript deduplication | Parked | Automatic echo suppression risks deleting legitimate repeated speech without a representative measured corpus. Canonical transcripts remain untouched. |
| #28 Privacy plugins | Completed with a simplifying decision | Capture-only notification/menu-bar/Desktop filtering ships. Record will not mutate Focus or global SystemUIServer/Finder preferences. |

Closed ideas remain discoverable in GitHub and summarized in the ROADMAP; they
can be reopened with a concrete use case and a smaller acceptance boundary.
