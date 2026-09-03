#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root"

./scripts/ci/check-local-only.sh
./scripts/ci/test-local-only-guard.sh
./scripts/ci/test-model-downloader-boundary.sh
./scripts/ci/test-model-installer.sh
./scripts/ci/test-local-signing.sh
./scripts/ci/test-dmg-layout.sh
./scripts/ci/test-podman-cli.sh
./scripts/ci/test-app-stamp.sh
./scripts/ci/test-ci-app-artifact.sh
./scripts/ci/test-parakeet-model-pack.sh
./scripts/ci/test-release-ci-provenance.sh
swift format lint --strict --configuration .swift-format --recursive \
    Package.swift Sources/RecordCore Sources/RecordCapture Sources/RecordMedia \
    Sources/RecordModelDownload Sources/RecordModelDownloaderService \
    Sources/Record/AppUpdateController.swift \
    Sources/Record/Audio/SessionAudioFinalizer.swift \
    Sources/Record/AudioSessionInspector.swift \
    Sources/Record/CapturePrivacyPreferences.swift \
    Sources/Record/ExportDirectoryAccess.swift Sources/Record/FluidAudioOfflinePolicy.swift \
    Sources/Record/FinishedVideoExporter.swift Sources/Record/GifskiHandoff.swift \
    Sources/Record/LaunchAtLoginController.swift \
    Sources/Record/Notify.swift Sources/Record/Record.swift \
    Sources/Record/RecordingSession.swift \
    Sources/Record/RecordingMode.swift Sources/Record/RecordingPermission.swift \
    Sources/Record/SessionMediaInspector.swift \
    Sources/Record/UI/MenuBarController.swift \
    Sources/Record/UI/MenuBarCameraArtwork.swift \
    Sources/Record/UI/MenuBarRecordingIndicatorView.swift \
    Sources/Record/UI/RecordingMenuPresentation.swift \
    Sources/Record/RecordingNamePreferences.swift \
    Sources/Record/Transcription/MacWhisperEngine.swift \
    Sources/Record/Transcription/ParakeetModelDownloadClient.swift \
    Sources/Record/Transcription/ParakeetModelInstaller.swift \
    Sources/Record/Transcription/FoundationModelTranscriptAdviser.swift \
    Sources/Record/Transcription/TranscriptionCoordinator.swift \
    Sources/Record/Transcription/TranscriptionPreferences.swift \
    Sources/Record/VideoCaptureProfile.swift Sources/Record/VideoRecordingSession.swift \
    Tests/RecordCoreTests Tests/RecordTests Tests/RecordCaptureTests Tests/RecordMediaTests \
    Tests/RecordModelDownloadTests
git diff --check
echo "source contract gate passed"
