# macOS 27 readiness

Status: macOS 27 Golden Gate and Xcode 27 are beta software as of 2026-08-07.
This gate is tracked by [issue #45](https://github.com/aindaco1/record/issues/45).

## Current findings

- Apple's current [macOS 27 release notes](https://developer.apple.com/documentation/macos-release-notes/macos-27-release-notes)
  do not identify a ScreenCaptureKit, AVFoundation, ServiceManagement, or
  UserNotifications migration that requires a Record code change. Recheck on
  every beta and at RC rather than treating that as a final compatibility
  guarantee.
- [Xcode 27](https://developer.apple.com/documentation/xcode-release-notes/xcode-27-release-notes)
  includes Swift 6.4 and the macOS 27 SDK, runs only on Apple silicon, and can
  still build for Record's macOS 15 deployment target. Record is already
  Apple-silicon-only, so no Rosetta compatibility path should be introduced.
- GitHub's [`xcode-27` runner](https://github.com/actions/runner-images/issues/14404)
  is a public preview hosted on macOS 26 with the macOS 27 SDK. It is useful for
  compiler and SDK diagnostics, but it cannot exercise macOS 27 runtime or TCC
  behavior. Its CI result stays advisory until GitHub marks the image GA.
- Xcode 27 beta 4's Swift Build engine compiles Record but does not stage the
  transitive Sparkle binary framework beside `RecordTests`, so its test helper
  cannot load that bundle. The defect is reported upstream as
  [swift-package-manager#10384](https://github.com/swiftlang/swift-package-manager/issues/10384).
  The preview lane still compiles with Swift Build, then runs the complete suite
  and release build with SwiftPM's native engine. Remove that split after the
  upstream packaging defect is fixed and a full default-engine run passes.
- macOS 27 can require Apple's
  [background-inference entitlement](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.background-tasks.continued-processing.inference)
  for Neural Engine work while an app is inactive. Parakeet currently uses
  FluidAudio's Core ML models, so inactive-app transcription is the only known
  Record-specific beta risk. Do not add an entitlement speculatively: first
  reproduce on the latest beta, then verify that the narrow entitlement works
  with Developer ID signing, notarization, the sandbox, and Record's visible
  menu-bar lifecycle. A CPU fallback is acceptable for diagnosis, not as an
  unnoticed permanent performance regression.

## Automated preview gate

The `xcode-27-compatibility` CI job uses the same `scripts/ci/validate.sh` entry
point as stable CI, selecting only SwiftPM's build engine through a validated
environment option. It must remain DRY and content-free. While the runner is in
preview, failures are triaged and linked to #45 but do not block a pull request.
At Xcode 27 GA:

1. pin the supported GA runner/toolchain;
2. remove `continue-on-error` after one green run;
3. keep the stable release job until packaging, signing, Sparkle, and
   notarization gates pass under Xcode 27;
4. move release packaging only after those gates pass; and
5. retain the macOS 15 deployment target unless an intentional product decision
   changes support.

## Signed-app runtime matrix

Use synthetic media on an Apple-silicon Mac running the latest macOS 27 beta or
RC. Record the OS build, Xcode build, Record commit, signing identity class, and
TCC state without recording window titles, device names, transcripts, or media.

- Upgrade with Record already authorized. Confirm the signed app retains its
  microphone, Screen & System Audio Recording, and System Audio Recording Only
  assignments and does not repeat granted prompts.
- Capture the main display, one picker display, one application, one independent
  window, and a custom region. Confirm the video-only MOV plus independent
  24-bit PCM system and microphone WAV files finalize and export.
- Exercise repeated pause/resume and force-quit during pause and segment
  rotation. Relaunch and confirm immutable segment recovery is idempotent.
- Switch among built-in, USB, and Bluetooth microphone routes when available;
  verify bounded recovery, monotonic audio duration, and no callback work.
- Start Parakeet transcription, make another app active, and leave Record's
  menu closed. Confirm inference completes at expected speed. If it fails only
  while inactive, capture content-free Core ML diagnostics and evaluate the
  background-inference entitlement before changing compute units.
- Confirm completion notifications open Finder, **Settings → General → Open
  Record at Login** accurately tracks `SMAppService`, and a signed Sparkle check
  can download and install a newer
  notarized test build without adding a network entitlement to the main app.

No beta-only workaround may weaken sandboxing, local-only behavior, signing
identity stability, update verification, or immutable-media recovery. Remove a
workaround if Apple resolves the underlying beta defect.
