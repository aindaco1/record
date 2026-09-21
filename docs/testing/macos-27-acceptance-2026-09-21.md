# macOS 27 acceptance — September 21, 2026

This report supplements the September 15 baseline originally tracked in
[issue #81](https://github.com/aindaco1/record/issues/81). All remaining manual
acceptance criteria now continue in [issue #6](https://github.com/aindaco1/record/issues/6).
Issue #81 was superseded through scope consolidation; none of its unchecked
rows became a passing result, and this report does not establish a new release.

## Environment and installed app

- Physical Apple Silicon Mac with its built-in display only.
- macOS 27.0 (`26A428`), Xcode 27.0 (`27A266a`).
- Installed public Record 1.4.3, build 20. This runtime test does not exercise
  the subsequently merged Sparkle 2.10.0 dependency.
- Existing user account, existing microphone and screen-capture access, and
  an already installed local Parakeet model.
- Installed bundle TCC identity and embedded-entitlement checks passed.
  Gatekeeper accepted the notarized Developer ID app, and stapler validation
  passed. No signing identity or entitlement was changed for these tests.

## Additional observed results

| Check | Result and boundary |
| --- | --- |
| Main-display capture | A roughly 23-second recording with synthetic source windows and synthetic speech finalized successfully. A sampled exported frame showed both test windows on the synthetic backdrop, with the expected display framing. |
| Media structure | Video-only HEVC MOV, 1728 × 1116, 22.633 seconds. Independent stereo 48 kHz, 24-bit PCM WAVs: system audio 22.592 seconds, microphone 22.571 seconds. The local media inspector passed. This is structural validation, not a listening-based channel-quality assessment. |
| Normal pause/resume | A separate session recorded start, pause, resume and stop events across two segments and finalized successfully. Its fixture was not consistently synthetic, so it is retained only as supplementary lifecycle evidence; no media or transcript is published. It does not cover interrupted-session recovery. |
| Open Record at Login | The existing enabled checkbox changed to disabled and back to enabled through Record Settings without an error. Approval-required presentation and an actual login launch were not exercised, so the combined login acceptance row remains open. |
| Pending source selection | Quitting while awaiting a source selection returned cleanly without leaving an active recording. This does not prove picker selection or selected-source loss. |
| Cleanup | Record was left idle with Main Display selected, the original export destination restored, all three capture-privacy settings enabled, and Open Record at Login enabled as before. Test fixture applications were stopped. |

Media, transcripts, session metadata, diagnostics and source hashes remain
local. Early fixture attempts hid when inactive; those recordings are excluded
from synthetic-scope acceptance. The corrected fixture stayed visible when
inactive, and an exported frame was inspected before counting the main-display
result. No capture-related product defect was established by this pass.

## Remaining acceptance

The user requested that further desktop tests be skipped for now. All of these
checks remain open in issue #6:

- **Transferred macOS 27 checks:** grant persistence across an actual signed
  upgrade, with all three TCC services verified separately; full picker-display, application,
  independent-window and controlled custom-region scope checks; selected-source
  loss; forced termination while paused, resuming and rotating/finalizing;
  immutable-media and idempotent recovery checks; notification reveal and
  synthetic-notification exclusion; login approval-state presentation; and
  clean-account first-run, model setup and uninstall acceptance.
- **Physical displays:** multiple-display and cable-disconnect/reconnect
  testing. No external display is available, so this cannot be completed on
  the current hardware arrangement.
- **Existing hardware and recovery checks:** USB microphone reconnect,
  Bluetooth profile changes, call-length route-change recording, ordinary Desktop Spaces, and capture
  permission revocation classified as `permissionDenied`.

Menu-bar and system-picker accessibility was inconsistent in the desktop
automation tools. AppleScript/System Events operated Record's menu and settings
after explicit user authorization, but did not establish the picker matrix.
An uncontrolled region recording is excluded from scope acceptance. Tool
accessibility failures and interruptions are not evidence of product failure.

Hosted Xcode 27 results and remaining toolchain-promotion gates are tracked
separately in [the readiness report](macos-27-readiness.md) and
[issue #80](https://github.com/aindaco1/record/issues/80).
