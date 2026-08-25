#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root"

swift_build_system="${RECORD_SWIFT_BUILD_SYSTEM:-native}"
case "$swift_build_system" in
    native | swiftbuild)
        swift_build_arguments=(--build-system "$swift_build_system")
        ;;
    *)
        echo "unsupported Swift build system: $swift_build_system" >&2
        exit 1
        ;;
esac

./scripts/ci/check-local-only.sh
./scripts/ci/test-local-only-guard.sh
./scripts/ci/test-model-installer.sh
./scripts/ci/test-local-signing.sh
./scripts/ci/test-dmg-layout.sh
./scripts/ci/test-podman-cli.sh
swift format lint --strict --configuration .swift-format --recursive \
    Package.swift Sources/RecordCore Sources/RecordCapture Sources/RecordMedia \
    Sources/Record/AppUpdateController.swift \
    Sources/Record/AudioSessionInspector.swift \
    Sources/Record/CapturePrivacyPreferences.swift \
    Sources/Record/ExportDirectoryAccess.swift Sources/Record/FluidAudioOfflinePolicy.swift \
    Sources/Record/FinishedVideoExporter.swift Sources/Record/GifskiHandoff.swift \
    Sources/Record/LaunchAtLoginController.swift \
    Sources/Record/Notify.swift Sources/Record/Record.swift \
    Sources/Record/RecordingMode.swift Sources/Record/RecordingPermission.swift \
    Sources/Record/UI/MenuBarController.swift \
    Sources/Record/RecordingNamePreferences.swift \
    Sources/Record/Transcription/MacWhisperEngine.swift \
    Sources/Record/Transcription/TranscriptionCoordinator.swift \
    Sources/Record/Transcription/TranscriptionPreferences.swift \
    Sources/Record/VideoCaptureProfile.swift Sources/Record/VideoRecordingSession.swift \
    Tests/RecordCoreTests Tests/RecordTests Tests/RecordCaptureTests Tests/RecordMediaTests
resolved_before="$(shasum -a 256 Package.resolved | awk '{print $1}')"
swift package resolve
resolved_after="$(shasum -a 256 Package.resolved | awk '{print $1}')"
if [[ "$resolved_before" != "$resolved_after" ]]; then
    echo "swift package resolve changed Package.resolved" >&2
    git diff -- Package.resolved >&2
    exit 1
fi
swift test "${swift_build_arguments[@]}"
swift build "${swift_build_arguments[@]}" -c release --arch arm64

binary_path="$(
    swift build "${swift_build_arguments[@]}" -c release --arch arm64 --show-bin-path
)/record"
architectures="$(lipo -archs "$binary_path")"
if [[ "$architectures" != "arm64" ]]; then
    echo "expected an arm64-only binary, found: $architectures" >&2
    exit 1
fi
