# Local-only enforcement

Record treats screenshots, recordings, transcripts, clipboard content and
clipboard-derived names, plugin state, diagnostics, and file metadata as
private local data. The product has no accounts, telemetry, cloud
transcription, upload, or capture-data network path. Network access is confined
to sandboxed helpers: Sparkle checks and installs signed application updates,
and the Parakeet downloader fetches one pinned GitHub model asset only after an
explicit user request.

## Defense in depth

1. Product-source CI rejects common Apple networking frameworks, client APIs,
   raw sockets, remote URL construction, telemetry SDKs, and network command
   execution outside the dedicated model downloader. A separate helper guard
   permits Foundation `URLSession` but rejects configurable remote URLs, raw
   sockets, command-line download tools, and additional entitlements. Both
   guards have positive and negative fixture tests.
2. The distributed main app is sandboxed and intentionally omits both outgoing
   and incoming network entitlements. Sparkle's separately sandboxed downloader
   and installer XPC services are the narrow exception for launch and manual
   update requests; the appcast and archive both require Ed25519 signatures.
   `RecordModelDownloader.xpc` is the separate, outbound-only exception for the
   explicit Parakeet setup action.
3. Record enables FluidAudio's offline mode at every executable entry point
   and immediately before model preparation. A test calls FluidAudio's public
   download surface and requires its typed `networkDisabled` failure.
4. Release signing embeds the reviewed entitlement files, and CI extracts both
   the main-app and model-helper entitlements from the signed artifact rather
   than trusting only source configuration.
5. Models enter through either a user-selected local folder or the explicit
   **Download and Install** action. The helper selects the fixed asset itself,
   receives only an open private-file descriptor, and verifies the archive
   before writing. The main app independently verifies it again, expands it in
   private temporary storage, and accepts only the pinned per-file manifest
   through the same atomic importer.
6. Plugin capabilities do not include networking. Future plugin helpers must
   use the same network-denying sandbox policy.
7. The optional MacWhisper adapter uses Apple's `NSUserUnixTask` mechanism and
   a fixed wrapper in Record's Application Scripts directory. The wrapper
   validates MacWhisper's Developer ID on every run and forwards exact
   arguments without evaluation. This deliberately runs outside Record's
   sandbox because MacWhisper's CLI requires its local Unix socket. It does not
   persist history and never runs as an automatic fallback.
8. The updater makes one silent background check against Record's public GitHub
   release feed at launch; **Check for Updates…** remains a manual fallback.
   Automatic installation and Sparkle system profiling are disabled. Sparkle
   accepts only a Developer ID signed, Apple-notarized release whose update
   signatures match the public key embedded in Record.
9. Optional readability refinement uses only Apple's on-device
   `SystemLanguageModel`. Record submits bounded, escaped classification records
   and accepts only revalidated keep/remove decisions. It uses no networking
   API or entitlement and preserves the raw local transcript whenever output
   changes.
10. Screenshot capture uses native ScreenCaptureKit and ImageIO only. Pixels
    are written directly to the approved local export root and the local
    pasteboard; no screenshot history, preview database, OCR, upload, or editor
    is created. Full-display and area commands request direct screen access;
    window/application capture uses Apple's selection-scoped private picker.

FluidAudio currently contains download-capable APIs even though Record calls
only its local existence and loading APIs. This is why the sandbox boundary is
required in addition to source scanning. Dependency updates must be reviewed
for new network, telemetry, process-launch, file-access, and model-loading
behavior before merge.

## Required capabilities

The app sandbox permits microphone input plus read/write access to locations
explicitly selected by the user. Persistent access uses app-scoped security
bookmarks. Record 1.x currently omits camera access. Screen and system-audio
capture remain protected by macOS privacy consent and their Info.plist usage
descriptions; they do not require a network entitlement.

Finished session and screenshot exports default to Desktop, but Desktop is
only a suggested location until the user approves it through Record's folder
picker. The resulting app-scoped bookmark is stored in the app container and
its access lifetime is balanced explicitly. Record atomically validates a
complete external session before deleting its finalized private working copy.
Any export or validation failure preserves the private original, and cleanup
refuses paths outside the direct session root.

Screenshots reuse that same balanced security-scoped bookmark. They are
published through a hidden temporary file, validated as the requested image
type and pixel dimensions, and collision-safely renamed. A JPEG is flattened
onto white; the clipboard independently receives lossless PNG. Partial failure
preserves whichever local result succeeded and reports no captured content in
the notification.

## Boundary and limitations

- CI and release hosts use the network to fetch reviewed source dependencies,
  actions, signing/notarization services, and publish artifacts. They never
  receive user recordings or application diagnostics.
- A launch/explicit update check or an explicit Parakeet model request discloses
  the ordinary connection metadata of a request to GitHub and its release-asset
  host. Neither path includes recording data, transcript text, clipboard
  content, session metadata, diagnostics, local paths, or a Record account
  identifier.
- The developer-only Parakeet setup script remains available outside the app
  sandbox. The shipping app uses a different, fixed-asset XPC path and does not
  enable FluidAudio's downloader.
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
./scripts/ci/test-model-downloader-boundary.sh
./scripts/ci/validate.sh
```

For a signed artifact, inspect and validate the embedded policy:

```sh
codesign --display --entitlements - --xml Record.app
codesign --display --entitlements - --xml \
  Record.app/Contents/XPCServices/RecordModelDownloader.xpc
./scripts/ci/check-signed-entitlements.sh Record.app
```
