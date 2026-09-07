# Source selection and pause/recovery acceptance

Date: September 7, 2026. Scope: [issue #9](https://github.com/aindaco1/record/issues/9)
and [issue #26](https://github.com/aindaco1/record/issues/26). The listed live
pause/recovery checks for #26 are complete on this host. Issue #9 has remaining
acceptance qualifications below. Both GitHub issues were left open at the end of
the acceptance session; #26 is ready to close when these fixes merge. This report
does not establish completion of #9's remaining qualifications.

## Environment and method

- Baseline: installed Record 1.4.0, build 17, with source equivalent to main
  `f269177` for the application and tests. Intervening changes were docs/tooling.
- Candidate: signed local 1.4.1-local, build 18, containing the changes in this
  review. This is local validation, not a published release or updater result.
- Final candidate executable SHA-256:
  `34549ee52163e66f0840337ab65c11aa20c0fa279eb8417016f3bcc1acf5b178`.
- Host: Apple M1 Max, arm64, macOS 26.6.2 (25G83), built-in Retina display.
- Strict recursive signature, TCC identity, and signed entitlement checks passed
  for the installed baseline. Existing capture and Accessibility grants were
  used. The main app retains no incoming or outgoing network entitlement.
- Reused OwlSwitch's test-only `CGVirtualDisplay` fixture under its shared desktop
  lock. It installs no driver and restores the original topology on teardown.
  Fixture creation, enumeration, and restoration passed at 1920 × 1080 @1,
  1280 × 720 @1 and @2, 1440 × 900 @1, and left/above display placements.
  Those are fixture capabilities; live Record capture used 1280 × 720 @1 and @2.
- Captured a local synthetic pattern application with a moving marker and a
  separate magenta decoy application. The decoy makes application isolation
  observable. Actual media, temporary helpers, source identifiers, and private
  session metadata remain local and are not committed.
- Record's menu-only UI was unavailable through the normal app-window automation
  surface. The user authorized a scoped local Accessibility helper. It operates
  Record, the Apple picker, and the disposable synthetic source using existing
  permissions. Transition interruption is conditional on observing the exact
  pause/resume state, not a guessed delay.

## Defects found and local changes

### Application selection was widened to the display

The native picker returned an application-only filter with display-bound style,
one included application, and no included windows. Record classified it as a
whole display and rebuilt the filter, including the unrelated magenta decoy in
an application recording. A genuine display choice had empty inclusion lists.

`CaptureSelectionScope` now distinguishes the scope using the public inclusion
lists. The shared recording/screenshot resolver retains narrow filters and only
rebuilds verified whole-display filters. The signed local retest excluded the
visible decoy while retaining both windows of the selected synthetic application.
On macOS 15.0–15.1, ambiguous display-bound picker results fail closed because
those inspection APIs are unavailable; Main Display and direct region recording
remain available. See [ADR 0019](../adr/0019-selected-source-lifetime.md).

### Selected application exit did not stop the stream

The baseline kept recording for over 20 seconds after the selected synthetic
process exited. With the scope correction alone, the properly restricted stream
still kept running for another ten-second observation. A scoped application
termination observer now reports one sanitized `sourceUnavailable` failure
through the existing stop/recovery path.

The signed local retest ignored an unrelated application's exit, then stopped in
0.223 seconds after the selected application exited. The failed manifest had the
expected classification. Its HEVC MOV and independent system/microphone AAC/CAF
segments remained present and decoded fully without errors (about 5.7 seconds).
No process identifiers, names, or new source metadata are persisted. Already
classified startup failures retain their classification through session cleanup;
a deterministic session test verifies cancellation occurs exactly once.

### Region overlays were displaced off secondary displays

On a Retina virtual display, the expected global overlay frame began at
(1728, 0) in Accessibility coordinates, but the panel appeared at (3456, -397).
The AppKit initializer interprets its origin relative to its supplied screen;
Record had supplied the global origin again. The shared recording/screenshot
region panel now initializes with a local zero origin and sets its exact global
frame. Regression tests cover right, left, and above display placements without
requiring TCC or capture hardware. The signed retest selected a 400 × 300 point
region on the secondary Retina display and produced an 800 × 600 MOV containing
the expected synthetic green quadrant. Video and both independent WAV files
decoded completely (about 4.5 seconds).

### Stop during Resume could leave a missing-track failure

A normal SIGINT quit delivered after observing **resuming screen recording…**
waited for rotation but stopped before every requested writer had its first
sample. The session retained its completed first segment but failed with
`writerFailed` instead of producing the final MOV/WAV export.

Start and Resume now wait for processed samples from video and every requested
audio track, outside capture callbacks and the media worker. The wait is bounded
to five seconds; cancellation and missing-track errors still preserve recovery
media. See the refinement in [ADR 0009](../adr/0009-crash-safe-pause-segments.md).
Signed retests delivered SIGINT only after observing pausing/resuming state.
Both finalized a video-only 2560 × 1440 MOV plus separate 48-kHz stereo 24-bit
PCM WAV files. All outputs decoded fully without errors, and private raw working
directories were removed only after validated export.

## Live acceptance results

| Area | Observation | Result |
|---|---|---|
| Display @1 | 1280 × 720 logical/pixel output, video-only HEVC MOV, separate 24-bit PCM WAV files | Passed on baseline |
| Display @2 | 1280 × 720 logical display produced 2560 × 1440 video; opaque synthetic pattern framed correctly | Passed on baseline |
| Application isolation | Unselected decoy appeared before the scope correction and was excluded afterward | Passed on signed local scope fix |
| Application exit | Unrelated exit ignored; selected exit stopped with classified failure and playable independent recovery segments | Passed on signed local scope/lifetime fix |
| Independent window | Selected window produced 640 × 392 video @1 and 1280 × 784 @2, including its title bar | Passed in signed app |
| Window close | Definitive NSWindow deallocation while the owner remained alive; Record returned to idle with `sourceUnavailable` and three fully decodable raw segments (about 3.7 seconds) | Passed on signed local build |
| Virtual display removal | Removing the selected display returned Record to idle with `sourceUnavailable`; three playable raw segments preserved | Passed on baseline; physical cable/hardware not exercised |
| Source-mode persistence | Relaunch retained system-picker mode and the next start requested fresh private source details | Passed in signed app |
| Repeated pause/resume | Three captured intervals, stable counter during pauses, Stop while paused finalized all outputs | Passed on baseline; indicator separately verified on candidate |
| Recording indicator | Cropped only Record’s own status item: pulsing red dot while active, no red dot in eight paused samples, red dot returned after Resume; paused counter stable | Passed on signed local build |
| Paused crash | Force quit after a completed pause; relaunch marked interruption and preserved all three completed files | Passed on baseline |
| Resume/finalization crash | SIGKILL delivered only after observing the respective rotation state; completed first segment retained | Passed on signed local build; settled manifests interrupted, completed media unchanged, second scan unchanged |
| Rotation lock | Stop and audio-only actions were disabled in the observed pausing/resuming states | Passed in signed local app |
| Stop during rotation | SIGINT during Resume reproduced missing-track failure; readiness fix added | Passed on signed local readiness fix for both Resume and pause finalization |
| Custom region @2 | 400 × 300 point selection on virtual secondary display produced an 800 × 600 MOV with correct framing and independent WAV files | Passed on signed local overlay fix |
| Native full-screen transition | Selected application entered and exited native full screen; recording continued and exported all three playable outputs (about 56.3 seconds) | Passed; separate desktop-Space switching remains unverified |
| Permission revocation | User authorized the temporary change and authenticated in System Settings; grant visibly off, app idle, complete 23.4-second export; original grant restored and candidate capture verified afterward | Safe stop/export observed; classified permission-failure requirement not established |

The repeated-pause export contained 47.883 seconds of video from roughly
90 seconds of wall time. Independent WAV durations were 47.872 and 47.659 seconds,
with manifest offsets accounting for source startup. Video presentation timestamps
were strictly increasing across 1,390 decoded frames. All three files decoded
completely; MOV contained only video and both WAVs were 48-kHz stereo 24-bit PCM.
The private raw directory was removed only after complete export validation.
No listening comparison with a known external audio fixture was performed.

For video decode inspection, preserve presentation timestamps when remuxed segments
contain discard/preroll packets; a default null-output mux can otherwise report
its own timestamp-rounding warnings:

```sh
ffmpeg -v error -i recording.mov -fps_mode passthrough -enc_time_base demux -f null -
```

## Automated validation

The initial focused suite passed 74 tests with one expected external multitrack
fixture skip. Added deterministic coverage for selection scope, application
lifetime, notification ownership, missing sources at startup, and readiness of
all requested writers. Policy/adapter tests require no TCC or recording hardware.
The final `./scripts/ci/local-gate.sh` passed after all code corrections. It
includes full validation, 342 tests (one expected external multitrack fixture
skip), source/privacy guards, ASan and TSan runs, signing/entitlement checks,
and package/checksum validation. The final focused session, failure-mapping,
and region suite passed 15 tests without failures.

Ignored logs and content-free result summaries live under
`.build/qa/issues-9-26/`. Captures, session manifests, recovery media, and pattern
frames remain in local test/export storage. No media or private metadata was
uploaded or added to the repository.

## Remaining acceptance

Follow the existing [manual smoke and interruption procedures](../testing.md#manual-smoke-test-available-now)
and [hardware matrix](../testing.md#current-macos-hardware-matrix). Complete the
remaining #9 qualifications before closing it:

- Desktop-Space switching was not established. Native full-screen entry and exit
  were visibly exercised, but a separate read-only Space observer reported no
  transition notifications, and the normal desktop/Mission Control automation
  surface was unavailable. Do not infer a broader desktop-Space pass.
- The permission-change/relaunch flow stopped and finalized the disposable
  recording normally. It did not produce a `permissionDenied` failure, so it
  does not establish that exact checklist outcome. Both original Record grants
  were visibly on after restoration; a relaunched candidate recorded and
  exported successfully. Accepting graceful stop/export in place of a classified
  failure requires an explicit replacement scope for that issue.

The #26 pause, indicator, rotation, forced-quit, repeated recovery, and final
media checks now have live results on this host. A virtual display exercises
native topology and scale behavior; it does not establish physical cable,
display-firmware, sleep/wake, or cross-machine behavior.

## Local teardown

The original display topology was restored, synthetic sources and diagnostic
helpers were stopped, and Record was left idle. The original Desktop export
folder, Main Display source mode, and existing capture permissions are restored.
The signed local candidate remains installed with Settings open for review.
The installed public release, GitHub issue states, and published assets were
not changed.
