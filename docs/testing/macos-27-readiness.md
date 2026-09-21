# macOS 27 readiness

Status: reviewed September 21, 2026. Apple has released macOS 27.0
(`26A428`) and Xcode 27.0 (`27A266a`). The physical test host runs those
versions. GitHub has deployed the released Xcode toolchain, but still labels
its `xcode-27` runner image as **public preview**. Apple toolchain availability
and GitHub runner GA are separate requirements.

[Issue #80](https://github.com/aindaco1/record/issues/80) owns hosted toolchain
promotion. [Issue #81](https://github.com/aindaco1/record/issues/81) owns remaining
signed-app runtime acceptance. The five existing route, Desktop Spaces and
permission-revocation outcomes remain in
[issue #6](https://github.com/aindaco1/record/issues/6). The closed
[issue #45 audit](https://github.com/aindaco1/record/issues/45#issuecomment-5683144299)
retains the September 15 release evidence with its original scope.

## Hosted default-engine evidence

The complete, unmodified `swift test` invocation passed on the hosted image at
source `ae9eb755d956fc97b5564e4bf165934ff3e099e6` in the
[September 21 compatibility job](https://github.com/aindaco1/record/actions/runs/35642857550/job/106476194654):

- macOS 27.0, build `26A5406e`;
- Xcode 27.0, build `27A266a`, Swift 6.4 (`swiftlang-6.4.0.34.1`);
- 344 XCTest cases across all six test targets, one expected external-fixture
  skip, and zero failures;
- Sparkle-linked application tests loaded and ran without manually staging the
  framework or changing the dependency graph.

That job passed. A separate stable packaging job in the same workflow hit a
transient `hdiutil` resource-unavailable error, so the workflow as a whole is
not successful release evidence.

This direct result satisfies the default-engine trial required before removing
the split-engine workaround for
[SwiftPM #10384](https://github.com/swiftlang/swift-package-manager/issues/10384).
The compatibility lane now runs the shared `scripts/ci/validate.sh --full` gate
with `RECORD_SWIFT_BUILD_SYSTEM=swiftbuild`, covering source contracts, the
complete tests, the locked dependency graph and the arm64 release build with
one engine. It logs the OS, compiler, Xcode build and source commit.

The resulting shared-gate implementation at
`fa511cc1cb897397673c319bf79bc793bbf66cf3` passed the
[complete hosted workflow](https://github.com/aindaco1/record/actions/runs/35644095847),
including the Xcode 27 compatibility job, stable tests, sanitizers and packaging.
The full local gate also passed on the physical macOS 27 host. The stable
packaging failure in the earlier trial did not recur.

The job remains advisory while the runner is in preview. Authoritative CI,
CodeQL and signed-release tooling still select Xcode 26.3. The verified CI app
handoff still requires that exact toolchain; no release attestation, signature,
entitlement or provenance check is relaxed by this compatibility change.

## Upstream review

- [Apple's release index](https://developer.apple.com/news/releases/) and
  [Xcode 27 release notes](https://developer.apple.com/documentation/xcode-release-notes/xcode-27-release-notes)
  establish the released toolchain. Record retains macOS 15 and Apple Silicon
  support; the newer SDK does not change the deployment target.
- [GitHub's runner announcement](https://github.com/actions/runner-images/issues/14404)
  still identifies `xcode-27` as preview. The
  [Xcode rollout issue](https://github.com/actions/runner-images/issues/14709)
  confirms deployment of the RC/GA toolchain, not graduation of the runner
  image to GA.
- Review of the released
  [macOS 27 notes](https://developer.apple.com/documentation/macos-release-notes/macos-27-release-notes)
  found no additional mandatory ScreenCaptureKit, ServiceManagement or
  UserNotifications migration for Record. The AVFAudio route-change fix does
  not replace physical route testing. Record uses `SMAppService`, not custom
  login LaunchAgents.
- Apple's background Neural Engine restriction remains documented. The
  September 15 signed 1.4.3 audit already demonstrated inactive local Parakeet
  completion on this OS release. Preserve that evidence without inferring all
  compute paths or devices are covered. Do not add an inference entitlement or
  silently force CPU fallback without a reproduced failure and a reviewed fix.
- Sparkle 2.10.0 raises its minimum macOS version to 12, below Record's 15
  minimum, and updates installer/file handling for macOS 27. Dependency review
  and the full local gate cover packaging, helper signing, network denial and
  the signed test feed. A future shipped version still needs real updater
  installation acceptance; a dependency merge alone does not establish it.

## Promotion gates

1. Confirm GitHub explicitly marks the runner GA, then pin the supported
   runner/toolchain and require the compatibility check after a green run.
2. Run the full local and hosted packaging gates under Xcode 27. Verify the
   embedded entitlements and stable TCC identity, Developer ID signatures,
   notarization, signed Sparkle feed/archive and downloaded-package readback.
3. Change the authoritative CI, CodeQL, release selector and exact-commit app
   provenance contract together. The restored app must remain the exact
   executable that passed authoritative CI; never substitute a local rebuild.
4. Update contributor, testing and release guidance and ADR 0012 when that
   durable toolchain decision is made. Retain the macOS 15 deployment target,
   Apple Silicon architecture and no-network main app.

No new signed release is required solely to update this tracker. Local package
checks, hosted compile/test evidence, public artifact verification and hardware
acceptance are distinct results.

## Signed-app runtime matrix

The [September 21 acceptance report](macos-27-acceptance-2026-09-21.md)
records the additional installed-app checks and the remaining limits. Desktop
testing stopped at the user's request; the incomplete rows remain open.

Use a supported Developer ID signed release, synthetic windows and synthetic
speech. Verify the fixture is visibly present before starting capture. Keep
all media, transcripts, clipboard content, diagnostics and private paths local.
Record only app version/build or source commit, OS build, hardware category,
permission state, duration, media-inspector results and observed outcomes.

- Verify microphone, Screen & System Audio Recording and System Audio
  Recording Only grants separately before and after an actual signed upgrade.
  A matching signing identity alone does not prove persistence.
- Exercise main display, picker display, application, independent window and
  custom region. Check selection scope and framing, a video-only MOV, and
  independent 24-bit PCM WAV tracks.
- Exercise selected-source loss and forced quit while paused, resuming and
  rotating/finalizing segments. Compare preserved media hashes and verify
  idempotent recovery. Retain normal pause/resume evidence separately.
- Test actual multiple displays and physical cable removal/reconnection.
  Virtual displays and a built-in-only host cannot satisfy that row.
- Verify completion/transcript notifications reveal the correct exported
  session, and capture-privacy settings exclude visible synthetic notifications.
- Exercise login registration, approval-state presentation and unregistering
  through `SMAppService`, restoring the original setting afterward.
- Complete clean-account first-run permission, recording/recovery, model setup
  and uninstall checks. Existing-account updater results do not cover these.

Keep unchecked rows in their owning issue until they have explicit passing
evidence or an explicit scope decision preserves them elsewhere.
