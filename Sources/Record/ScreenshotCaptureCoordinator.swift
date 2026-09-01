import AppKit
import CoreGraphics
import Foundation
import RecordCapture
import RecordCore

enum ScreenshotCaptureCoordinatorError: Error, Equatable {
    case displayUnavailable
}

struct ScreenshotCaptureOutput: Sendable {
    let savedURL: URL?
    let saveFailure: String?
    let copiedToClipboard: Bool
    let clipboardFailure: String?

    var isCompleteSuccess: Bool {
        savedURL != nil && copiedToClipboard
    }
}

private struct SendableScreenshotImage: @unchecked Sendable {
    let value: CGImage
}

private struct ScreenshotEncodingResults: Sendable {
    let diskData: Data?
    let diskFailure: String?
    let pngData: Data?
    let pngFailure: String?
}

/// Coordinates the three user-facing screenshot selectors while keeping
/// ScreenCaptureKit, encoding, disk publication, pasteboard, and sound behind
/// narrow adapters. AppController owns the one-operation-at-a-time policy.
@MainActor
final class ScreenshotCaptureCoordinator {
    private let adapter = ScreenCaptureScreenshotAdapter()
    private let picker: SystemScreenCapturePicker
    private let regionSelector: RegionSelectionController
    private let pasteboard: ScreenshotPasteboardWriter
    private let shutterSound: ScreenshotShutterSound

    init(
        picker: SystemScreenCapturePicker,
        regionSelector: RegionSelectionController,
        pasteboard: ScreenshotPasteboardWriter = ScreenshotPasteboardWriter(),
        shutterSound: ScreenshotShutterSound = ScreenshotShutterSound()
    ) {
        self.picker = picker
        self.regionSelector = regionSelector
        self.pasteboard = pasteboard
        self.shutterSound = shutterSound
    }

    func capture(
        kind: ScreenshotCaptureKind,
        privacy: CapturePrivacyConfiguration,
        format: ScreenshotImageFormat,
        jpegQuality: Double,
        exportDirectory: URL,
        playShutterSound: Bool,
        recordingIsActive: Bool,
        capturedAt: Date = Date()
    ) async throws -> ScreenshotCaptureOutput {
        let image = try await captureImage(kind: kind, privacy: privacy)

        // The audible cue corresponds to pixels being captured. Suppress it
        // during recording so it cannot bleed into a live microphone track.
        if ScreenshotFeedbackPolicy.shouldPlayShutter(
            preferenceEnabled: playShutterSound,
            recordingIsActive: recordingIsActive
        ) {
            shutterSound.play()
        }

        let imageBox = SendableScreenshotImage(value: image)
        let encoding = await Task.detached(priority: .userInitiated) {
            Self.encode(
                image: imageBox,
                format: format,
                jpegQuality: jpegQuality
            )
        }.value

        var copied = false
        var clipboardFailure = encoding.pngFailure
        if let pngData = encoding.pngData {
            do {
                try pasteboard.writePNG(pngData)
                copied = true
            } catch {
                clipboardFailure = String(describing: error)
            }
        }

        var savedURL: URL?
        var saveFailure = encoding.diskFailure
        if let diskData = encoding.diskData {
            let publication = await Task.detached(priority: .utility) {
                () -> Result<URL, StringError> in
                do {
                    return .success(
                        try ScreenshotExporter().publish(
                            data: diskData,
                            image: imageBox.value,
                            format: format,
                            directory: exportDirectory,
                            capturedAt: capturedAt
                        )
                    )
                } catch {
                    return .failure(StringError(String(describing: error)))
                }
            }.value
            switch publication {
            case .success(let url): savedURL = url
            case .failure(let error): saveFailure = error.message
            }
        }

        return ScreenshotCaptureOutput(
            savedURL: savedURL,
            saveFailure: saveFailure,
            copiedToClipboard: copied,
            clipboardFailure: clipboardFailure
        )
    }

    private func captureImage(
        kind: ScreenshotCaptureKind,
        privacy: CapturePrivacyConfiguration
    ) async throws -> CGImage {
        switch kind {
        case .display:
            guard let displayID = ScreenshotDisplayLocator.displayID() else {
                throw ScreenshotCaptureCoordinatorError.displayUnavailable
            }
            return try await adapter.captureDisplay(
                displayID: displayID,
                privacy: privacy
            )
        case .windowOrApplication:
            let selection = try await picker.select(
                mode: .windowOrApplication,
                privacy: privacy
            )
            return try await adapter.captureSelection(selection, privacy: privacy)
        case .area:
            let selection = try await regionSelector.selectRegion()
            return try await adapter.captureRegion(
                displayID: selection.displayID,
                rect: selection.rect,
                pointPixelScale: selection.pointPixelScale,
                privacy: privacy
            )
        }
    }

    nonisolated private static func encode(
        image: SendableScreenshotImage,
        format: ScreenshotImageFormat,
        jpegQuality: Double
    ) -> ScreenshotEncodingResults {
        let encoder = ScreenshotImageEncoder()
        let png: Result<Data, StringError>
        do {
            png = .success(try encoder.encode(image.value, format: .png))
        } catch {
            png = .failure(StringError(String(describing: error)))
        }

        let disk: Result<Data, StringError>
        if format == .png {
            disk = png
        } else {
            do {
                disk = .success(
                    try encoder.encode(
                        image.value,
                        format: .jpeg,
                        jpegQuality: jpegQuality
                    )
                )
            } catch {
                disk = .failure(StringError(String(describing: error)))
            }
        }

        return ScreenshotEncodingResults(
            diskData: try? disk.get(),
            diskFailure: disk.failure?.message,
            pngData: try? png.get(),
            pngFailure: png.failure?.message
        )
    }
}

private struct StringError: Error, Sendable {
    let message: String

    init(_ message: String) {
        self.message = message
    }
}

private extension Result {
    var failure: Failure? {
        guard case .failure(let error) = self else { return nil }
        return error
    }
}

/// Plays only the bundled, immutable shutter asset. Missing resources fail
/// silently so screenshot capture itself never depends on audio playback.
@MainActor
final class ScreenshotShutterSound {
    private lazy var sound: NSSound? = {
        guard let url = Bundle.main.url(forResource: "Shutter", withExtension: "mp3") else {
            return nil
        }
        return NSSound(contentsOf: url, byReference: true)
    }()

    func play() {
        sound?.stop()
        sound?.volume = 0.28
        sound?.play()
    }
}
