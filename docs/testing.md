# Testing strategy

Record separates deterministic logic from hardware/TCC behavior so most
regressions run on every pull request.

## Automated on every pull request

- typed configuration defaults and validation
- capture configuration limits and lifecycle command/effect transitions
- ScreenCaptureKit plan translation, source resolution, failure mapping,
  timestamp monotonicity, bounded queue depth, and idempotent stream cleanup
- fixed-capacity media and audio-writer ingress eviction, one-shot health
  events, off-callback conversion/writes, exact silence padding, failure
  cleanup, deterministic draining, and shared-timeline mapping under delay,
  gaps, and clock regression
- hardware-required HEVC/AAC writer settings, collision-safe independent video
  and audio paths, and empty-segment finalization without publishing invalid media
- display-profile and picker-derived 4K/even-dimension bounds, memory-only
  source-mode persistence, region coordinate conversion, video-session orchestration,
  bounded fresh-stream startup retries, classified failure manifests,
  idempotent stops, atomic whole-session exports, and contained source cleanup
- model identifier validation, local-only failure behavior, pinned SHA-256
  verification, symbolic-link rejection, and atomic model replacement
- command-scoped permission ordering, exact TCC service selection, and
  one-shot recording-intent recovery across a privacy restart, including
  one-time transfer of the successful audio-only permission tap into capture
- session state transitions and atomic manifest round trips
- interrupted-session recovery, playable-partial promotion, byte-preserving
  corrupt quarantine, content-free recovery summaries, live-process protection,
  at-most-once completion-hook claims, and path traversal rejection
- microphone route-recovery state transitions plus conservative transcript echo
  suppression that retains backchannels, unrelated overlap, and a raw sidecar
- manifest-derived recent-recording discovery plus symlink and nesting rejection
- failed-transcription retry menu state and no-op behavior without a failed job
- deterministic folder collision handling
- plugin activation rollback, reverse restoration, and idempotence
- native login-item state mapping and fail-closed approval handling
- stable Developer ID bundle/team/designated-requirement checks for TCC grants
- update menu wiring plus package checks for the Sparkle framework, feed
  configuration, signature requirements, XPC Mach services, and main-app
  network-entitlement denial
- local-only source/entitlement guards and FluidAudio network denial
- debug tests plus an arm64 release build and architecture check
- the complete suite under ThreadSanitizer and AddressSanitizer
- Swift formatting for new modular code

Future pure tests will cover edit-operation serialization, segment recovery,
click-event mapping, and out-of-process plugin capability denial.

## Manual smoke test available now

The current integrated build supports main-display, application, window, and
region video; audio-only recording; and the capture-privacy, recording-name,
and Gifski handoff plugins. Camera overlays, pause/resume, editing, and an
external plugin host are not yet integrated, so those rows in the hardware
matrix remain future acceptance criteria.

Use synthetic or non-sensitive content for development recordings:

1. Run `./script/build_and_run.sh --verify`, or use the Codex `Run` action.
   This builds arm64, assembles the real app bundle, signs it with the first
   available Developer ID or Apple Development identity plus the reviewed
   sandbox entitlements, verifies those embedded entitlements, and leaves
   `~/Applications/Record.app` running. Set `RECORD_CODESIGN_IDENTITY` to
   override the selection. With no Apple identity it falls back to ad hoc
   signing and warns that TCC grants will not survive a rebuild. The Record
   ring should appear in the menu bar. On first launch, allow notifications;
   Record requests access before the first completion event so recording and
   transcript banners cannot be lost to a late authorization prompt.
2. Choose **Start screen recording**. Record should request microphone access
   first when needed, followed by **Screen & System Audio Recording**. It must
   not request **System Audio Recording Only** or open System Settings itself.
   If you choose Open System Settings and enable Record, Privacy & Security
   should terminate the old process; Record should reopen and resume the Start
   command once. On first use, also approve Desktop in the export-folder picker.
3. Move a test window, speak into the selected microphone, and play a known
   local audio clip for at least 15 seconds. Confirm the ring pulses white (or
   remains steady white when Reduce Motion is enabled), the menu shows an
   increasing elapsed time, and the command becomes **Stop recording**.
4. Stop recording and wait for **saving recording…** to return to idle. Confirm
   a template-named session directory appears on Desktop containing
   `session.json`, video-only `recording.mov`, and independently playable
   `mic.caf` and `system.caf`. Open the MOV in QuickTime and confirm the main
   display has the expected aspect ratio; the mic file should contain your
   voice and the system file the played clip. Confirm the finalized private
   working directory no longer appears in **Open temp session**.
5. Revoke **System Audio Recording Only**, then choose **Start audio-only
   recording**. Record should request microphone access when needed, followed
   by System Audio Recording Only. It must not request screen capture. After a
   changed toggle, confirm Record replaces its process and begins the requested
   audio-only recording without creating a failed session first.
6. Inspect the audio-only session with
   `./scripts/qa/inspect-audio-session.sh "/path/to/session"`. It requires a
   finalized schema-v1 manifest, both named tracks, valid nonempty CAF files,
   readable durations, and nonnegative synchronization offsets.
7. Listen to `mic.caf` and `system.caf`. The microphone track should contain
   your voice; the system track should contain the played clip. Note silence,
   channel leakage, distortion, timing drift, or the wrong input device.
   Repeat once without headphones while the test clip plays through speakers.
   The raw mic may contain residual bleed, but the readable transcript should
   not duplicate aligned system dialogue; if suppression occurs,
   `transcript.raw.json` must retain the unsuppressed segments.
8. Confirm the complete audio-only session appears in the approved Desktop
   folder, its private working directory is removed, and **Audio recording
   ready** opens the exported folder in Finder. When transcription completes,
   confirm **Transcript ready** opens that same folder. Quit and reopen Record,
   then choose **Open last recording** and confirm Finder reveals that session.
9. Quit Record from its menu. Rerun with `--logs` for unified process logs or
   `--debug` for LLDB when investigating a failure.

Repeat the screen flow with each **Screen source** mode. For the system picker,
select one display, one application, and one independent window; close the
source during one disposable recording and confirm Record stops and preserves
the session. For **Custom Region…**, select a display, drag a region that does
not include private content, and confirm the MOV dimensions and framing match
the selection. Relaunch and confirm only the selected mode persists: Record
must ask for the source again and must not retain a window title, app name,
display identifier, or region.

Choose **Open at Login**, confirm Record appears in System Settings → General →
Login Items, then disable it again. If macOS reports that approval is required,
the menu should show a mixed state and open the Login Items pane without
re-registering repeatedly. A first `.notFound` state must still leave the menu
item enabled so registration can proceed.

Open **Plugins → Recording Name Template…**, test date/time and bundled-word
tokens, then use a synthetic clipboard value with `{clipboard}`. Confirm unsafe
path punctuation is removed, a duplicate name receives a numeric suffix, and
disabling **Rename Finished Recording** restores the plain legacy name. Never
use sensitive clipboard content in a development test.

With Gifski installed, record and stop a short synthetic video, then choose
**Plugins → Open Last Video in Gifski**. Confirm Gifski receives the existing
MOV and Record neither downloads a helper nor creates another media copy.

Also exercise these negative paths before a release candidate:

- deny microphone permission and verify recording fails without leaving a
  live half-session;
- revoke System Audio Recording access in System Settings and verify the error
  identifies the relevant permission;
- switch the default microphone during a recording; the menu should briefly
  report reconnection, the same `mic.caf` should continue, and its duration
  should include the silent route gap;
- record silence and an unplugged/reconnected external microphone; route
  retries must remain bounded and stopping must not leave an input tap alive;
- interrupt a recording with sleep/wake, then with Quit Record, and inspect the
  resulting session each time;
- in a disposable temp session, force termination while each independent media
  writer has a hidden `.partial` file. Relaunch: playable containers should be
  promoted, invalid containers should appear intact under
  `Recovery/Corrupt Media`, and a second relaunch should make no further moves;
- record for 30 minutes while watching memory, file growth, and menu timing.

Never paste a recording, transcript, model, or private path into a public issue.
Report the app commit, macOS version, Mac model, permission state, duration,
track formats from the inspector, and a description using synthetic content.

## Transcription engine checks

Install the default development model once, then use the signed sandboxed app
for the real test:

```sh
./scripts/setup/install-parakeet-model.sh
./script/build_and_run.sh --verify
```

Stop a short audio-only recording and confirm `transcript.json` and
`transcript.md` appear in its session directory. For the optional MacWhisper
path, first run `./scripts/setup/install-macwhisper-cli.sh`, then choose
**Transcript model → MacWhisper (Small)** in the Record menu and repeat the
audio-only check. Switch back with **Parakeet (Default)**. A failed track must
be reported in `transcribe.log` without deleting either CAF file, and a job
where every available track fails must not create a successful transcript.
After a failure, choose **Transcript model → Retry Failed Transcription**
and confirm the action disappears while the job runs and a successful retry
creates the canonical transcript without changing either source file.
Screen and audio-only sessions use the same independent CAF inputs for local
transcription; selecting an engine affects whichever finalized session is
queued next.

For the first-run path, temporarily move the sandbox's Parakeet v3 cache aside,
launch Record, and confirm the setup prompt appears without blocking recording.
Download the exact pinned revision from `docs/models/parakeet.md`, import it,
and confirm pending transcription resumes. Modify one byte in a disposable
download and confirm Record rejects it without changing an existing installed
model. The MacWhisper menu choice must be absent when either MacWhisper, its
bundled `mw`, or Record's user-script bridge is missing.

## Export folder access

In the signed sandboxed app, choose **Select export folder…** from the menu, approve
Desktop, record a short screen session and a short audio-only session, quit, and
relaunch. The item tooltip should still show Desktop, both complete session
directories should export without another prompt, and each finalized private
working copy should be removed only after its Desktop copy validates. Click the
completion and transcript notifications and confirm Finder selects each Desktop
session. Move or revoke the selected folder, relaunch, and confirm Record resets
the saved grant without changing or deleting unexported private session media.

## Update checks

Update cryptography and packaging are automated by
`scripts/release/generate-appcast.sh` and the release gate. After publishing a
release, install the prior notarized version on a clean test account, choose
**Check for Updates…**, and verify the new version, release notes, download,
replacement, and relaunch. Confirm a same-version check reports no update.

Before updating, grant all three Record privacy services and capture a short
screen and audio-only session. After updating 1.0.2 to 1.0.3, confirm the
toggles still identify Record as enabled and neither recording mode repeats an
already-approved prompt. Run
`./scripts/ci/check-tcc-identity.sh /Applications/Record.app` on both builds;
the reported bundle/team pair and designated requirement must match.

Do not test against an unsigned ad hoc archive. The production feed must reject
an archive with a changed byte, a feed with a changed byte after signing, an
unexpected signing key, or a missing Developer ID/notarization chain.

## macOS hardware matrix

Hardware tests run only on a dedicated Apple Silicon runner with intentional
TCC grants and synthetic, non-sensitive media.

| Area | Required cases |
|---|---|
| Source selection | each display, one window, one application, custom region, source disappears mid-session |
| Video | 1080p30, 1080p60, 4K30, 4K60, Retina scaling, HDR-to-SDR policy |
| Audio | mic only, system only, both, device switch, route reconfigure, silence, write failure |
| Camera | built-in/external, disconnect/reconnect, overlay positions and sizes |
| Input effects | cursor on/off, click highlight on/off, multiple displays and scale factors |
| Lifecycle | pause/resume, sleep/wake, lock/unlock, permission denial/revocation, low disk, forced quit |
| Recovery | termination before first frame, during each segment, during finalization, during plugin activation/restoration |
| Plugins | notification state, clock mask, desktop icon presentation, names, playback speed/audio pitch, Gifski handoff |

## Performance gates

Use signposts and Instruments rather than wall-clock guesses. On the reference
Mac, release candidates must demonstrate:

- no sustained dropped frames during a 30-minute 4K60 capture
- less than 50 ms A/V drift over one hour
- bounded memory across a one-hour recording
- no unbounded capture queue growth
- finalization in about two seconds when no transform is requested

Performance captures contain only generated test patterns and synthetic audio.
They are never uploaded automatically.
