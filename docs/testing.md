# Testing strategy

Record separates deterministic logic from hardware/TCC behavior so most
regressions run on every pull request.

## Automated on every pull request

- typed configuration defaults and validation
- capture configuration limits and lifecycle command/effect transitions
- ScreenCaptureKit plan translation, source resolution, failure mapping,
  timestamp monotonicity, bounded queue depth, and idempotent stream cleanup
- fixed-capacity media ingress eviction, metrics, failure cleanup, deterministic
  draining, and shared-timeline mapping under delay, gaps, and clock regression
- hardware-required HEVC/AAC writer settings, collision-safe partial paths, and
  empty-segment finalization without publishing invalid media
- display-profile 4K/even-dimension bounds, video-session orchestration,
  failure manifests, idempotent stops, and atomic non-overwriting exports
- model identifier validation and local-only failure behavior
- unified recording-permission setup ordering, cancellation, and no-capture
  behavior with injected TCC adapters
- session state transitions and atomic manifest round trips
- interrupted-session recovery, live-process protection, and path traversal rejection
- deterministic folder collision handling
- plugin activation rollback, reverse restoration, and idempotence
- local-only source/entitlement guards and FluidAudio network denial
- debug tests plus an arm64 release build and architecture check
- the complete suite under ThreadSanitizer and AddressSanitizer
- Swift formatting for new modular code

Future pure tests will cover transcript merging, edit-operation serialization,
segment recovery, click-event mapping, and plugin capability denial.

## Manual smoke test available now

The current integrated build supports main-display video plus the inherited
audio-only workflow. Camera overlays, source selection, pause/resume, editing,
and NewKap-style plugins are not yet integrated, so those rows in the hardware
matrix remain future acceptance criteria.

Use synthetic or non-sensitive content for development recordings:

1. Run `./script/build_and_run.sh --verify`, or use the Codex `Run` action.
   This builds arm64, assembles the real app bundle, signs it ad hoc with the
   reviewed sandbox entitlements, verifies those embedded entitlements, and
   leaves Record running. A feather should appear in the menu bar.
2. Choose **Set Up Recording Permissions…**. Record should show one explanation,
   then ask macOS to register both **Screen & System Audio Recording** and
   **System Audio Recording Only**, in that order. Apple may show one native
   confirmation for each independent permission. Choose Allow when prompted;
   the setup itself must not create a recording or media file. The settings
   page should open with Record present in both lists without using the `+`
   buttons. macOS still requires you to control each toggle. If it requests a
   relaunch, Record should reopen itself after the old process exits. If it
   does not, reopen the same signed app bundle without rebuilding it and report
   the failure.
3. Choose **Start screen recording**. On first use, approve Desktop in the
   export-folder picker and grant microphone access if macOS prompts.
4. Move a test window, speak into the selected microphone, and play a known
   local audio clip for at least 15 seconds. Confirm the feather turns red, the
   menu shows an increasing elapsed time, and the command becomes **Stop
   recording**.
5. Stop recording and wait for the menu to return to idle. Confirm a nonempty
   template-named `.mov` appears on Desktop, opens in QuickTime,
   shows the main display at the expected aspect ratio, and contains both the
   microphone and played system audio. Record keeps the raw `recording.mov` in
   **Open session storage** for recovery.
6. Repeat with **Start audio-only recording**, then inspect that session with
   `./scripts/qa/inspect-audio-session.sh "/path/to/session"`. It requires a
   finalized schema-v1 manifest, both named tracks, valid nonempty CAF files,
   readable durations, and nonnegative synchronization offsets.
7. Listen to `mic.caf` and `system.caf`. The microphone track should contain
   your voice; the system track should contain the played clip. Note silence,
   channel leakage, distortion, timing drift, or the wrong input device.
8. Quit Record from its menu. Rerun with `--logs` for unified process logs or
   `--debug` for LLDB when investigating a failure.

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
- switch the default microphone between recordings;
- record silence and an unplugged/reconnected external microphone;
- interrupt a recording with sleep/wake, then with Quit Record, and inspect the
  resulting session each time;
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
**Transcription → MacWhisper (Small)** in the feather menu and repeat the
audio-only check. Switch back with **Parakeet (Default)**. A failed track must
be reported in `transcribe.log` without deleting either CAF file, and a job
where every available track fails must not create a successful transcript.
Video-session audio extraction/transcription is a follow-up; selecting an
engine currently affects audio-only sessions.

## Export folder access

In the signed sandboxed app, choose **Export folder: Desktop…** from the menu,
approve Desktop, record a short video, quit, and relaunch. The menu should still
show Desktop, the video should export without another prompt, and the raw
session copy should remain private. Move or revoke the selected folder,
relaunch, and confirm Record resets the saved grant without changing or
deleting raw session media.

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
