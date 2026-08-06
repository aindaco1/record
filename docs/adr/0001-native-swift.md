# ADR 0001: Build Record as a native Swift macOS application

- Status: accepted
- Date: 2026-08-06

## Decision

Use Swift 6 with AppKit and SwiftUI. Capture and media processing use
ScreenCaptureKit, AVFoundation, VideoToolbox, Core Media, and Metal directly.
Support macOS 15+ on Apple Silicon only.

## Rationale

Record's difficult work is entirely platform-native: screen-content selection,
TCC permissions, menu-bar behavior, hardware codecs, camera/microphone access,
signing, and notarization. Tauri would add a webview, command bridge, and second
type system without providing portability that this project intends to use.

## Consequences

- Native APIs and concurrency checking are available without an IPC bridge.
- UI tests and capture tests require macOS runners.
- Portable domain logic remains isolated in `RecordCore`.
- A future cross-platform product would require a new decision rather than
  quietly weakening the native architecture.
