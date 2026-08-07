# GitHub issue scope for Record 1.1.0

Record 1.1.0 is the first feature release after the intentionally narrow 1.0
series. Its scope is limited to four issues; their GitHub acceptance
criteria remain canonical so this document does not duplicate evolving task
lists.

| Issue | 1.1.0 outcome | Release evidence |
|---|---|---|
| [#6](https://github.com/aindaco1/record/issues/6) Microphone route recovery | Complete representative device acceptance for the recovery implementation shipped in 1.0.3. | USB disconnect/reconnect, Bluetooth profile changes, and a call-length route change in the signed app. |
| [#9](https://github.com/aindaco1/record/issues/9) Source selection | Select a display, application, independent window, or display-local region without retaining sensitive window titles. | Pure filter/configuration tests plus signed-app coverage for every source type, source loss, and permission revocation. |
| [#26](https://github.com/aindaco1/record/issues/26) Pause and resume | Rotate compatible immutable media segments, recover every interruption boundary, and concatenate without re-encoding. | State, manifest, filesystem, recovery, and race tests plus repeated pause/resume and forced-quit hardware coverage. |
| [#45](https://github.com/aindaco1/record/issues/45) macOS 27 readiness | Compile and test with the Xcode 27 preview while keeping stable release tooling and the macOS 15 deployment target. | Non-blocking preview CI plus a signed-app macOS 27 beta/RC smoke matrix, including inactive-app Parakeet inference. |

The release keeps microphone and system audio in separate source files, keeps
all recording state local, performs no media work on capture callbacks, and
retains raw segments until the exported session has been validated. Source UI
and pause UI must issue the existing typed commands rather than create parallel
capture state.

The Xcode 27 lane is advisory while GitHub labels its image a public preview.
It becomes a required release check after the image and toolchain reach general
availability. See `docs/testing/macos-27-readiness.md` for the evidence and
promotion criteria.

Recording history and configurable global shortcuts remain possible future
features in `ROADMAP.md`; they are not part of 1.1.0. A Homebrew Cask is no
longer planned. Camera, editing, cloud services, accounts, analytics, uploads,
and in-process third-party plugins remain outside this release.
