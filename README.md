# Record

Record is a private-by-design macOS recorder for screen video, system audio,
microphone audio, camera overlays, and on-device transcription. It keeps the
one-click menu-bar simplicity of Quill and the useful workflow ideas from
NewKap without Electron, cloud processing, or arbitrary plugins in the capture
process.

> [!IMPORTANT]
> Record is pre-alpha. The inherited Quill audio recorder builds and its new
> core is tested, but screen/video capture and the native app bundle are still
> being implemented. Do not rely on it as the only recorder for important work.

## Product constraints

- macOS 15 or newer
- Apple Silicon only
- Swift 6, AppKit, and SwiftUI
- ScreenCaptureKit, AVFoundation, VideoToolbox, and Metal
- local media and local inference only
- no accounts, analytics, recording uploads, or cloud transcription

The application itself does not download transcription models. A release will
include an offline model-import path and may bundle the default model. This
keeps recording and transcription usable without granting Record network
access.

## Current development build

```sh
swift build
swift test
swift run record doctor
swift run record
```

The current binary records microphone and system audio into independently
recoverable CAF tracks. A session starts with an atomic `session.json`
manifest and is finalized before transcription is queued.

For a real sandboxed app-bundle launch and the current manual audio checklist,
see [Testing](docs/testing.md). The project-local `./script/build_and_run.sh`
entrypoint is also available as the Codex `Run` action.

Optional configuration lives at `~/.config/record/config.json`:

```json
{
  "schema_version": 1,
  "recordings_directory": "~/Recordings",
  "transcription": {
    "enabled": true,
    "engine": "parakeet",
    "model": "parakeet-tdt-0.6b-v3-coreml"
  },
  "mic_voice_processing": false,
  "completion_hook": {
    "executable": "/absolute/path/to/local-tool",
    "arguments": ["--session", "{session}"]
  }
}
```

Completion hooks are executed directly. Record never passes configuration to a
shell, and hook executable paths must be absolute.

## Architecture and roadmap

- [Architecture](docs/architecture.md)
- [Quill issue and PR migration](docs/migration/quill-triage.md)
- [Native Swift decision](docs/adr/0001-native-swift.md)
- [Local-only security boundary](docs/adr/0002-local-only.md)
- [Plugin isolation](docs/adr/0003-plugin-isolation.md)
- [Contributing](CONTRIBUTING.md)
- [Security policy](SECURITY.md)

The `RecordCore` module contains platform-independent session, configuration,
model-registry, and plugin-lifecycle logic. Hardware and TCC-dependent capture
code stays behind narrow adapters so most behavior can be exercised in normal
unit tests.

## Provenance

Record is a new standalone project based on the MIT-licensed history of
[digimata/quill](https://github.com/digimata/quill). NewKap and its plugins are
used as product references; Record reimplements selected behaviors natively
instead of embedding Electron, FFmpeg, or legacy plugin code.

## License

MIT. See [LICENSE](LICENSE).
