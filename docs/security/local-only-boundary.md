# Local-only enforcement

Record treats recordings, transcripts, clipboard-derived names, plugin state,
diagnostics, and file metadata as private local data. The product has no
accounts, telemetry, cloud transcription, upload, model download, or in-app
update path.

## Defense in depth

1. Product-source CI rejects common Apple networking frameworks, client APIs,
   raw sockets, remote URL construction, telemetry SDKs, and network command
   execution. The guard has its own positive and negative fixture tests.
2. The distributed app is sandboxed. It intentionally omits both outgoing and
   incoming network entitlements, so linked dependency code cannot initiate a
   connection even if it contains a downloader.
3. Record enables FluidAudio's offline mode at every executable entry point
   and immediately before model preparation. A test calls FluidAudio's public
   download surface and requires its typed `networkDisabled` failure.
4. Release signing embeds the reviewed entitlement file, and CI extracts the
   signed entitlements to verify the actual artifact rather than trusting only
   source configuration.
5. Models enter through a user-selected local-file import. A missing model
   fails closed and is never fetched by the application.
6. Plugin capabilities do not include networking. Future plugin helpers must
   use the same network-denying sandbox policy.
7. The optional MacWhisper adapter uses Apple's `NSUserUnixTask` mechanism and
   a fixed wrapper in Record's Application Scripts directory. The wrapper
   validates MacWhisper's Developer ID on every run and forwards exact
   arguments without evaluation. This deliberately runs outside Record's
   sandbox because MacWhisper's CLI requires its local Unix socket. It does not
   persist history and never runs as an automatic fallback.

FluidAudio currently contains download-capable APIs even though Record calls
only its local existence and loading APIs. This is why the sandbox boundary is
required in addition to source scanning. Dependency updates must be reviewed
for new network, telemetry, process-launch, file-access, and model-loading
behavior before merge.

## Required capabilities

The app sandbox permits microphone and camera input plus read/write access to
locations explicitly selected by the user. Persistent access uses app-scoped
security bookmarks. Screen and system-audio capture remain protected by macOS
privacy consent and their Info.plist usage descriptions; they do not require a
network entitlement.

The preferences UI must migrate arbitrary configured output paths to a folder
picker and store a security-scoped bookmark before sandboxed releases. Until
that is complete, sandbox failures are product errors and must not be worked
around with broad temporary exceptions.

## Boundary and limitations

- CI and release hosts use the network to fetch reviewed source dependencies,
  actions, signing/notarization services, and publish artifacts. They never
  receive user recordings or application diagnostics.
- The developer-only Parakeet setup script downloads one immutable model
  revision outside the app sandbox. The model is installed into Record's local
  container; the shipping app neither contains nor calls the downloader.
- Enabling MacWhisper expands the trust boundary to the separately installed
  MacWhisper app. Record retains no network entitlement, but cannot enforce
  MacWhisper's behavior from outside its sandbox; use only an installed local
  model. Parakeet is the stricter default.
- `swift run` and other developer-built command-line executables are not
  sandboxed app launches. The source guard still applies, but the enforceable
  runtime boundary is the signed `.app` artifact.
- Static scanning is a regression tripwire, not a proof. Code review and the
  signed sandbox boundary remain mandatory.
- Opening a public documentation URL in the user's browser may be considered
  later, but Record must never place recording data, identifiers, or private
  metadata in that URL.

## Verification

Run the same checks as CI:

```sh
./scripts/ci/check-local-only.sh
./scripts/ci/test-local-only-guard.sh
./scripts/ci/validate.sh
```

For a signed artifact, inspect and validate the embedded policy:

```sh
codesign --display --entitlements - --xml Record.app
./scripts/ci/check-signed-entitlements.sh Record.app
```
