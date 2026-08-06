# Testing strategy

Record separates deterministic logic from hardware/TCC behavior so most
regressions run on every pull request.

## Automated on every pull request

- typed configuration defaults and validation
- model identifier validation and local-only failure behavior
- session state transitions and atomic manifest round trips
- deterministic folder collision handling
- plugin activation rollback, reverse restoration, and idempotence
- local-only source/entitlement guards and FluidAudio network denial
- debug tests plus an arm64 release build and architecture check
- the complete suite under ThreadSanitizer and AddressSanitizer
- Swift formatting for new modular code

Future pure tests will cover transcript merging, edit-operation serialization,
frame-timestamp normalization, queue backpressure, segment recovery, recording
name templates, click-event mapping, and plugin capability denial.

## Manual smoke test available now

The current integrated build supports the menu-bar lifecycle plus microphone
and system-audio recording. Screen video, camera overlays, source selection,
and NewKap-style plugins are not yet integrated, so those rows in the hardware
matrix are future acceptance criteria rather than claims about this build.

Use synthetic or non-sensitive content for development recordings:

1. Run `./script/build_and_run.sh --verify`, or use the Codex `Run` action.
   This builds arm64, assembles the real app bundle, signs it ad hoc with the
   reviewed sandbox entitlements, verifies those embedded entitlements, and
   leaves Record running. A feather should appear in the menu bar.
2. Choose **Start recording**. Grant microphone and Screen & System Audio
   Recording access to Record if macOS prompts. If macOS requests a relaunch,
   quit Record from its menu and rerun the command.
3. Speak into the selected microphone while playing a known local audio clip
   for at least 15 seconds. Confirm the feather turns red, the menu shows an
   increasing elapsed time, and **Start recording** becomes **Stop recording**.
4. Stop recording, confirm the menu returns to idle, and choose **Open
   recordings folder**. Do not force-quit while the stop is finalizing.
5. Inspect the new session with
   `./scripts/qa/inspect-audio-session.sh "/path/to/session"`. It requires a
   finalized schema-v1 manifest, both named tracks, valid nonempty CAF files,
   readable durations, and nonnegative synchronization offsets.
6. Listen to `mic.caf` and `system.caf`. The microphone track should contain
   your voice; the system track should contain the played clip. Note silence,
   channel leakage, distortion, timing drift, or the wrong input device.
7. Quit Record from its menu. Rerun with `--logs` for unified process logs or
   `--debug` for LLDB when investigating a failure.

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
