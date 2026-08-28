import AudioToolbox
import AVFoundation
import Foundation
import RecordCore

struct SessionAudioArtifact: Equatable, Sendable {
    let kind: SessionManifest.TrackKind
    let url: URL
}

protocol SessionAudioFinalizing: Sendable {
    func finalize(_ sources: [SessionAudioArtifact]) throws -> [SessionAudioArtifact]
}

/// Converts crash-resilient AAC/CAF capture files into the canonical WAV files
/// declared by a finalized session. Source CAF files remain untouched until
/// the complete exported session has been validated and private cleanup runs.
struct PCM24WaveAudioFinalizer: SessionAudioFinalizing {
    static let bitDepth = 24

    enum FinalizationError: Error, Equatable, CustomStringConvertible {
        case unsupportedTrack(SessionManifest.TrackKind)
        case duplicateTrack(SessionManifest.TrackKind)
        case unsafeSource(SessionManifest.TrackKind)
        case outputAlreadyExists(SessionManifest.TrackKind)
        case conversionFailed(SessionManifest.TrackKind)
        case promotionFailed

        var description: String {
            switch self {
            case .unsupportedTrack(let kind):
                return "unsupported audio track: \(kind.rawValue)"
            case .duplicateTrack(let kind):
                return "duplicate audio track: \(kind.rawValue)"
            case .unsafeSource(let kind):
                return "unsafe audio source: \(kind.rawValue)"
            case .outputAlreadyExists(let kind):
                return "audio output already exists: \(kind.rawValue)"
            case .conversionFailed(let kind):
                return "audio conversion failed: \(kind.rawValue)"
            case .promotionFailed:
                return "audio outputs could not be promoted"
            }
        }
    }

    private struct PreparedOutput {
        let artifact: SessionAudioArtifact
        let partialURL: URL
    }

    func finalize(_ sources: [SessionAudioArtifact]) throws -> [SessionAudioArtifact] {
        guard !sources.isEmpty else { return [] }
        let fileManager = FileManager.default

        var kinds: [SessionManifest.TrackKind] = []
        let prepared = try sources.map { source -> PreparedOutput in
            guard let outputFilename = Self.outputFilename(for: source.kind) else {
                throw FinalizationError.unsupportedTrack(source.kind)
            }
            guard !kinds.contains(source.kind) else {
                throw FinalizationError.duplicateTrack(source.kind)
            }
            kinds.append(source.kind)
            guard Self.isNonemptyRegularCAF(source.url) else {
                throw FinalizationError.unsafeSource(source.kind)
            }

            let destination = source.url.deletingLastPathComponent().appendingPathComponent(
                outputFilename,
                isDirectory: false
            )
            guard !fileManager.fileExists(atPath: destination.path) else {
                throw FinalizationError.outputAlreadyExists(source.kind)
            }
            let partial = destination.deletingLastPathComponent().appendingPathComponent(
                ".\(destination.deletingPathExtension().lastPathComponent)."
                    + "\(UUID().uuidString).partial.wav",
                isDirectory: false
            )
            return PreparedOutput(
                artifact: SessionAudioArtifact(kind: source.kind, url: destination),
                partialURL: partial
            )
        }

        defer {
            for output in prepared where fileManager.fileExists(atPath: output.partialURL.path) {
                try? fileManager.removeItem(at: output.partialURL)
            }
        }

        for (source, output) in zip(sources, prepared) {
            do {
                try Self.writeWave(from: source.url, to: output.partialURL)
            } catch {
                throw FinalizationError.conversionFailed(source.kind)
            }
        }

        var promoted: [URL] = []
        do {
            for output in prepared {
                try fileManager.moveItem(at: output.partialURL, to: output.artifact.url)
                promoted.append(output.artifact.url)
            }
        } catch {
            for url in promoted {
                try? fileManager.removeItem(at: url)
            }
            throw FinalizationError.promotionFailed
        }
        return prepared.map(\.artifact)
    }

    static func outputFilename(for kind: SessionManifest.TrackKind) -> String? {
        switch kind {
        case .microphone:
            return "mic.wav"
        case .systemAudio:
            return "system.wav"
        case .screen, .camera:
            return nil
        }
    }

    private static func writeWave(from sourceURL: URL, to destinationURL: URL) throws {
        let source = try AVAudioFile(forReading: sourceURL)
        let format = source.processingFormat
        guard source.length > 0, format.sampleRate > 0, format.channelCount > 0 else {
            throw CocoaError(.fileReadCorruptFile)
        }

        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: format.sampleRate,
            AVNumberOfChannelsKey: Int(format.channelCount),
            AVLinearPCMBitDepthKey: bitDepth,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ]
        let writtenFrames = try transcode(
            sourceURL: sourceURL,
            destinationURL: destinationURL,
            clientFormat: format,
            destinationSettings: settings
        )
        guard writtenFrames > 0 else {
            throw CocoaError(.fileReadCorruptFile)
        }

        let validation = try AVAudioFile(forReading: destinationURL)
        let stream = validation.fileFormat.streamDescription.pointee
        guard validation.length > 0,
            stream.mFormatID == kAudioFormatLinearPCM,
            stream.mBitsPerChannel == UInt32(bitDepth)
        else {
            throw CocoaError(.fileReadCorruptFile)
        }
    }

    private static func transcode(
        sourceURL: URL,
        destinationURL: URL,
        clientFormat: AVAudioFormat,
        destinationSettings: [String: Any]
    ) throws -> AVAudioFramePosition {
        let source = try AVAudioFile(forReading: sourceURL)
        let destination = try AVAudioFile(
            forWriting: destinationURL,
            settings: destinationSettings,
            commonFormat: clientFormat.commonFormat,
            interleaved: clientFormat.isInterleaved
        )
        guard
            let buffer = AVAudioPCMBuffer(
                pcmFormat: clientFormat,
                frameCapacity: 32_768
            )
        else {
            throw CocoaError(.fileReadCorruptFile)
        }

        var writtenFrames: AVAudioFramePosition = 0
        while source.framePosition < source.length {
            buffer.frameLength = 0
            try source.read(into: buffer, frameCount: buffer.frameCapacity)
            guard buffer.frameLength > 0 else { break }
            try destination.write(from: buffer)
            writtenFrames += AVAudioFramePosition(buffer.frameLength)
        }
        return writtenFrames
    }

    private static func isNonemptyRegularCAF(_ url: URL) -> Bool {
        guard url.isFileURL,
            url.pathExtension.lowercased() == "caf",
            let values = try? url.resourceValues(
                forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]
            )
        else { return false }
        return values.isRegularFile == true
            && values.isSymbolicLink != true
            && (values.fileSize ?? 0) > 0
    }
}
