import AVFoundation
import AudioToolbox
import Foundation
import RecordCapture
import RecordCore
import VideoToolbox

public struct SegmentWriterPlan: Equatable, Sendable {
    public static let minimumBitRate = 4_000_000
    public static let maximumBitRate = 50_000_000

    public let width: Int
    public let height: Int
    public let framesPerSecond: Int
    public let bitRate: Int
    public let includesSystemAudio: Bool
    public let includesMicrophone: Bool

    public init(configuration: CaptureConfiguration, bitRate: Int? = nil) throws {
        try configuration.validate()
        width = configuration.outputSize.width
        height = configuration.outputSize.height
        framesPerSecond = configuration.frameRate.rawValue
        let estimatedBitRate = Int(
            Double(width * height * framesPerSecond) * 0.1
        )
        self.bitRate =
            bitRate
            ?? min(
                Self.maximumBitRate,
                max(Self.minimumBitRate, estimatedBitRate)
            )
        guard (Self.minimumBitRate...Self.maximumBitRate).contains(self.bitRate) else {
            throw SegmentWriterError.invalidBitRate(self.bitRate)
        }
        includesSystemAudio = configuration.audio.includeSystemAudio
        includesMicrophone = configuration.audio.includeMicrophone
    }

    public func makeVideoSettings() -> [String: Any] {
        [
            AVVideoCodecKey: AVVideoCodecType.hevc,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoColorPropertiesKey: [
                AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
                AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
                AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2,
            ],
            AVVideoEncoderSpecificationKey: [
                kVTVideoEncoderSpecification_RequireHardwareAcceleratedVideoEncoder as String: true
            ],
            AVVideoCompressionPropertiesKey: [
                AVVideoExpectedSourceFrameRateKey: framesPerSecond,
                AVVideoAllowFrameReorderingKey: false,
                kVTCompressionPropertyKey_MaxKeyFrameIntervalDuration as String: 2.0,
                kVTCompressionPropertyKey_RealTime as String: true,
                kVTCompressionPropertyKey_AverageBitRate as String: bitRate,
                AVVideoProfileLevelKey: kVTProfileLevel_HEVC_Main_AutoLevel as String,
            ],
        ]
    }

    public func makeAudioSettings() -> [String: Any] {
        [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 48_000,
            AVNumberOfChannelsKey: 2,
            AVEncoderBitRateKey: 192_000,
        ]
    }
}

public struct SegmentOutput: Equatable, Sendable {
    public let finalURL: URL
    public let partialURL: URL

    public init(
        finalURL: URL,
        identifier: UUID = UUID(),
        fileManager: FileManager = .default
    ) throws {
        let pathExtension = finalURL.pathExtension.lowercased()
        guard finalURL.isFileURL,
            pathExtension == "mov" || pathExtension == "caf",
            !finalURL.hasDirectoryPath
        else {
            throw SegmentWriterError.invalidOutputURL
        }
        let standardizedURL = finalURL.standardizedFileURL
        guard !fileManager.fileExists(atPath: standardizedURL.path) else {
            throw SegmentWriterError.outputAlreadyExists(standardizedURL)
        }
        let parentURL = standardizedURL.deletingLastPathComponent()
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: parentURL.path, isDirectory: &isDirectory),
            isDirectory.boolValue
        else {
            throw SegmentWriterError.outputDirectoryUnavailable(parentURL)
        }

        self.finalURL = standardizedURL
        partialURL = parentURL.appendingPathComponent(
            ".\(standardizedURL.deletingPathExtension().lastPathComponent).\(identifier.uuidString).partial.\(pathExtension)",
            isDirectory: false
        )
    }
}

public struct SegmentOutputSet: Equatable, Sendable {
    public let outputs: [ScreenCaptureSampleKind: SegmentOutput]

    public init(
        finalURLs: [ScreenCaptureSampleKind: URL],
        identifier: UUID = UUID(),
        fileManager: FileManager = .default
    ) throws {
        guard finalURLs[.screen] != nil else {
            throw SegmentWriterError.invalidOutputURL
        }
        let standardizedURLs = finalURLs.values.map(\.standardizedFileURL)
        guard Set(standardizedURLs).count == standardizedURLs.count else {
            throw SegmentWriterError.invalidOutputURL
        }
        outputs = try Dictionary(
            uniqueKeysWithValues: finalURLs.map { kind, finalURL in
                (
                    kind,
                    try SegmentOutput(
                        finalURL: finalURL,
                        identifier: identifier,
                        fileManager: fileManager
                    )
                )
            }
        )
    }

    public init(
        screenURL: URL,
        includesSystemAudio: Bool,
        includesMicrophone: Bool,
        identifier: UUID = UUID(),
        fileManager: FileManager = .default
    ) throws {
        let directory = screenURL.deletingLastPathComponent()
        var finalURLs: [ScreenCaptureSampleKind: URL] = [.screen: screenURL]
        if includesSystemAudio {
            finalURLs[.systemAudio] = SessionMediaLayout.url(
                for: .systemAudio,
                stage: .capture,
                in: directory
            )!
        }
        if includesMicrophone {
            finalURLs[.microphone] = SessionMediaLayout.url(
                for: .microphone,
                stage: .capture,
                in: directory
            )!
        }
        try self.init(
            finalURLs: finalURLs,
            identifier: identifier,
            fileManager: fileManager
        )
    }

    public subscript(kind: ScreenCaptureSampleKind) -> SegmentOutput? {
        outputs[kind]
    }
}

public enum SegmentWriterError: Error, Equatable, Sendable {
    case invalidBitRate(Int)
    case invalidOutputURL
    case outputAlreadyExists(URL)
    case outputDirectoryUnavailable(URL)
    case writerCreationFailed
    case cannotAddTrack(ScreenCaptureSampleKind)
    case invalidState(AVAssetSegmentWriter.State)
    case writingFailed(CaptureFailure)
}
