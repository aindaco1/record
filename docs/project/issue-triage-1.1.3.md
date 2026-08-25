# GitHub issue and pull-request scope for Record 1.1.3

Record 1.1.3 is a security and dependency maintenance release. The live
GitHub tracker was reviewed on 2026-08-24 against the 1.1.2 source, current
hosted checks, and the local release candidate.

## Pull requests included

| Pull request | Release outcome |
|---|---|
| [#50](https://github.com/aindaco1/record/pull/50) Swift dependencies | Update FluidAudio to 0.15.6 and Sparkle to 2.9.6; retain the exact Sparkle pin, resolved revisions, offline model enforcement, and main-app network denial. |
| [#48](https://github.com/aindaco1/record/pull/48) GitHub Actions | Update both CodeQL action uses to the verified 4.37.7 commit and keep all third-party actions pinned by full revision. |

## Issues remaining open

No open issue describes an unimplemented software defect. The four open issues
track manual signed-app or hardware acceptance for features already shipped in
1.0.3 and 1.1.0. Their GitHub acceptance criteria remain canonical.

| Issue | Implemented state | Why it remains open |
|---|---|---|
| [#6](https://github.com/aindaco1/record/issues/6) Microphone route recovery | Route recovery, bounded retries, monotonic timing, and wired-headphone fallback shipped in 1.0.3. | USB disconnect/reconnect, Bluetooth profile changes, and a call-length route change still require representative connected hardware. |
| [#9](https://github.com/aindaco1/record/issues/9) ScreenCaptureKit source selection | Display, application, window, and custom-region selection shipped in 1.1.0; picker callback fixes shipped in 1.1.1. | Representative-display, source-loss, display-removal, Space-change, and permission-revocation signed-app rows remain. |
| [#26](https://github.com/aindaco1/record/issues/26) Crash-safe pause/resume | Immutable segments, serialized rotation, passthrough finalization, recovery, and deterministic coverage shipped in 1.1.0. | Repeated pause/resume and force-quit checks at each live capture boundary remain. |
| [#45](https://github.com/aindaco1/record/issues/45) macOS 27 and Xcode 27 | The advisory Xcode 27 build/test lane is green while retaining the macOS 15 deployment target and stable release toolchain. | The runner remains a public preview, and runtime/TCC/Parakeet acceptance requires a real Mac running macOS 27 beta or RC. |

Do not close these issues from dependency checks or a macOS 26 smoke test.
Future acceptance comments must distinguish deterministic test evidence from
observed signed-app hardware behavior and must not include captured content,
transcripts, device identifiers, or private paths.
