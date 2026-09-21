# macOS 27 readiness

Status: reviewed September 21, 2026. Apple has released macOS 27.0
(`26A428`) and Xcode 27.0 (`27A266a`). The physical test host runs those
versions. GitHub has deployed the released Xcode toolchain, but still labels
its `xcode-27` runner image as **public preview**. On September 21 the repository
owner explicitly approved using this preview infrastructure for required CI
and signed releases. This exception does not claim GitHub runner GA. The
released Xcode version and build are pinned; see
[ADR 0020](../adr/0020-xcode-27-release-toolchain.md).

[Issue #80](https://github.com/aindaco1/record/issues/80) owns authoritative
toolchain and release promotion. [Issue #6](https://github.com/aindaco1/record/issues/6)
is the single tracker for signed-app hardware and manual runtime acceptance.
It retains its five route, Desktop Spaces and permission-revocation outcomes
and all seven macOS 27 criteria transferred from
[issue #81](https://github.com/aindaco1/record/issues/81). Issue #81 is superseded;
consolidation does not establish any additional passing result. The closed
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
The trial then ran the shared `scripts/ci/validate.sh --full` gate with
`RECORD_SWIFT_BUILD_SYSTEM=swiftbuild`, covering source contracts, the complete
tests, the locked dependency graph and the arm64 release build with one engine.
Swift Build is now the shared gate's default engine.

The resulting shared-gate implementation at
`fa511cc1cb897397673c319bf79bc793bbf66cf3` passed the
[complete hosted workflow](https://github.com/aindaco1/record/actions/runs/35644095847),
including the Xcode 27 compatibility job, stable tests, sanitizers and packaging.
The full local gate also passed on the physical macOS 27 host. The stable
packaging failure in the earlier trial did not recur.

Authoritative build/package, sanitizer, CodeQL and signed-release jobs now use
`xcode-27` and require Xcode 27.0 build `27A266a`. The existing required
**Swift tests and arm64 build** context propagates a failed build; the redundant
advisory lane is removed. CI app handoff schema v3 binds both compiler version
and build, in addition to the existing exact-commit and executable checks.
Release attestations, signatures, entitlements and provenance remain required.

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

1. Use the owner-approved preview runner with released Xcode 27.0 build
   `27A266a`, selected by a versioned path and checked by exact version/build.
   The runner's preview status is an accepted infrastructure risk, not a
   signature, provenance or test exception.
2. Run the full local gate and required hosted build/package, sanitizer and
   CodeQL jobs. Before tagging, require successful full CI and CodeQL on the
   exact `main` commit and its retained, attested application.
3. Verify the Xcode 27 release's Developer ID signatures, embedded entitlements,
   stable TCC identity, notarization, signed Sparkle feed/archive and downloaded
   package. Reuse the attested CI executable; never substitute a local rebuild.
4. Maintain contributor, testing and release guidance and
   [ADR 0020](../adr/0020-xcode-27-release-toolchain.md), which amends ADRs 0010
   and 0012. Retain the macOS 15 deployment target, Apple Silicon architecture
   and no-network main app.

[Issue #80](https://github.com/aindaco1/record/issues/80) records completion
with exact workflow and public-release evidence. Local package checks, hosted
compile/test evidence, public artifact verification and hardware acceptance
remain distinct results. The owner also requested the 1.4.4 release and local
deployment; the preview exception does not waive outstanding #6 hardware rows.

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
