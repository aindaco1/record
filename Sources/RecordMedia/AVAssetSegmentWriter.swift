import AVFoundation
import CoreMedia
import Foundation
import RecordCapture
import RecordCore

public struct FinalizedSegmentArtifacts: Equatable, Sendable {
    public let files: [ScreenCaptureSampleKind: URL]
    public let startOffsetMilliseconds: [ScreenCaptureSampleKind: Int]

    public init(
        files: [ScreenCaptureSampleKind: URL],
        startOffsetMilliseconds: [ScreenCaptureSampleKind: Int] = [:]
    ) {
        self.files = files
        self.startOffsetMilliseconds = startOffsetMilliseconds
    }

    public subscript(kind: ScreenCaptureSampleKind) -> URL? {
        files[kind]
    }
}

public enum SegmentWriterResult: Equatable, Sendable {
    case empty
    case finalized(FinalizedSegmentArtifacts)
}

/// Serial real-time processor that writes screen video, system audio, and
/// microphone audio as independently usable files. Each writer starts from
/// the same ScreenCaptureKit clock anchor, preserving cross-track alignment
/// without forcing players to choose between alternate audio tracks in a MOV.
public final class AVAssetSegmentWriter: MediaSampleProcessing, @unchecked Sendable {
    public enum State: String, Equatable, Sendable {
        case configured
        case writing
        case finishing
        case completed
        case failed
    }

    public private(set) var state: State = .configured

    private let fileManager: FileManager
    private let tracks: [ScreenCaptureSampleKind: TrackWriter]

    private var timeline: CommonMediaTimeline?
    private var result: SegmentWriterResult?
    private var terminalFailure: CaptureFailure?
    private var preservesPartialOnFailure = false
    private var appendedSampleCount = 0

    public init(
        plan: SegmentWriterPlan,
        output: SegmentOutputSet,
        fileManager: FileManager = .default
    ) throws {
        self.fileManager = fileManager

        var tracks: [ScreenCaptureSampleKind: TrackWriter] = [:]
        do {
            guard let screenOutput = output[.screen] else {
                throw SegmentWriterError.invalidOutputURL
            }
            tracks[.screen] = try TrackWriter(
                kind: .screen,
                output: screenOutput,
                fileType: .mov,
                outputSettings: plan.makeVideoSettings()
            )
            if plan.includesSystemAudio, let systemOutput = output[.systemAudio] {
                tracks[.systemAudio] = try TrackWriter(
                    kind: .systemAudio,
                    output: systemOutput,
                    fileType: .caf,
                    outputSettings: plan.makeAudioSettings()
                )
            }
            if plan.includesMicrophone, let microphoneOutput = output[.microphone] {
                tracks[.microphone] = try TrackWriter(
                    kind: .microphone,
                    output: microphoneOutput,
                    fileType: .caf,
                    outputSettings: plan.makeAudioSettings()
                )
            }
        } catch let error as SegmentWriterError {
            tracks.values.forEach { $0.cancel(fileManager: fileManager) }
            throw error
        } catch {
            tracks.values.forEach { $0.cancel(fileManager: fileManager) }
            throw SegmentWriterError.writerCreationFailed
        }
        self.tracks = tracks
    }

    deinit {
        guard state != .completed, !preservesPartialOnFailure else { return }
        cancelAll(removePartials: true)
    }

    public func process(
        _ sample: ScreenCaptureSample
    ) throws -> MediaSampleProcessingResult {
        guard state == .configured || state == .writing else {
            throw SegmentWriterError.invalidState(state)
        }
        guard let track = tracks[sample.kind] else {
            return .dropped(.trackDisabled)
        }

        if state == .configured {
            do {
                try startAll(at: sample.timestamp.time)
                timeline = try CommonMediaTimeline(anchor: sample.timestamp.time)
                state = .writing
            } catch {
                let failure = CaptureFailure(
                    code: .encoderFailed,
                    summary: "media encoders failed to start"
                )
                transitionToFailure(failure, removePartials: true)
                throw MediaSampleProcessingFailure(failure)
            }
        }

        do {
            _ = try timeline?.position(
                for: sample.timestamp.time,
                kind: sample.kind
            )
        } catch {
            let failure = CaptureFailure(
                code: .writerFailed,
                summary: "media timestamps became invalid"
            )
            transitionToFailure(failure, removePartials: true)
            throw MediaSampleProcessingFailure(failure)
        }

        guard track.input.isReadyForMoreMediaData else {
            return .dropped(.writerBackpressure)
        }
        guard track.input.append(sample.buffer) else {
            let failure = CaptureFailure(
                code: .writerFailed,
                summary: "a media track could not accept a sample"
            )
            transitionToFailure(failure, removePartials: true)
            throw MediaSampleProcessingFailure(failure)
        }
        track.recordAppend(at: sample.timestamp.time)
        appendedSampleCount += 1
        return .consumed
    }

    public func finish() async throws -> SegmentWriterResult {
        switch state {
        case .configured:
            cancelAll(removePartials: true)
            state = .completed
            result = .empty
            return .empty

        case .writing:
            guard appendedSampleCount > 0 else {
                cancelAll(removePartials: true)
                state = .completed
                result = .empty
                return .empty
            }
            state = .finishing
        case .finishing:
            throw SegmentWriterError.invalidState(state)
        case .completed:
            return result ?? .empty
        case .failed:
            throw SegmentWriterError.writingFailed(
                terminalFailure
                    ?? CaptureFailure(code: .writerFailed, summary: "media tracks failed")
            )
        }

        guard tracks.values.allSatisfy({ $0.appendedSampleCount > 0 }) else {
            let failure = CaptureFailure(
                code: .writerFailed,
                summary: "one or more requested media tracks captured no samples"
            )
            transitionToFailure(failure, removePartials: false)
            throw SegmentWriterError.writingFailed(failure)
        }

        for kind in ScreenCaptureSampleKind.allCases {
            guard let track = tracks[kind] else { continue }
            track.input.markAsFinished()
            await track.finish()
        }

        guard tracks.values.allSatisfy({ $0.writer.status == .completed }) else {
            let failure = CaptureFailure(
                code: .writerFailed,
                summary: "media tracks could not be finalized"
            )
            transitionToFailure(failure, removePartials: false)
            throw SegmentWriterError.writingFailed(failure)
        }

        do {
            for kind in ScreenCaptureSampleKind.allCases {
                guard let output = tracks[kind]?.output else { continue }
                try fileManager.moveItem(at: output.partialURL, to: output.finalURL)
            }
        } catch {
            let failure = CaptureFailure(
                code: .writerFailed,
                summary: "finalized media tracks could not be promoted"
            )
            transitionToFailure(failure, removePartials: false)
            throw SegmentWriterError.writingFailed(failure)
        }

        let anchor = timeline?.anchor.time ?? .zero
        let finalized = FinalizedSegmentArtifacts(
            files: Dictionary(
                uniqueKeysWithValues: tracks.map { ($0.key, $0.value.output.finalURL) }
            ),
            startOffsetMilliseconds: Dictionary(
                uniqueKeysWithValues: tracks.compactMap { kind, track in
                    guard let firstTimestamp = track.firstTimestamp else { return nil }
                    let seconds = CMTimeGetSeconds(CMTimeSubtract(firstTimestamp, anchor))
                    guard seconds.isFinite else { return nil }
                    return (kind, max(0, Int((seconds * 1_000).rounded())))
                }
            )
        )
        let finalizedResult = SegmentWriterResult.finalized(finalized)
        result = finalizedResult
        state = .completed
        return finalizedResult
    }

    private func startAll(at anchor: CMTime) throws {
        for track in tracks.values {
            guard track.writer.startWriting() else {
                throw SegmentWriterError.writerCreationFailed
            }
            track.writer.startSession(atSourceTime: anchor)
        }
    }

    private func transitionToFailure(
        _ failure: CaptureFailure,
        removePartials: Bool
    ) {
        state = .failed
        terminalFailure = failure
        preservesPartialOnFailure = !removePartials
        cancelAll(removePartials: removePartials)
    }

    private func cancelAll(removePartials: Bool) {
        tracks.values.forEach {
            $0.writer.cancelWriting()
            if removePartials {
                try? fileManager.removeItem(at: $0.output.partialURL)
            }
        }
    }
}

private final class TrackWriter {
    let output: SegmentOutput
    let writer: AVAssetWriter
    let input: AVAssetWriterInput
    private(set) var appendedSampleCount = 0
    private(set) var firstTimestamp: CMTime?

    init(
        kind: ScreenCaptureSampleKind,
        output: SegmentOutput,
        fileType: AVFileType,
        outputSettings: [String: Any]
    ) throws {
        self.output = output
        do {
            writer = try AVAssetWriter(outputURL: output.partialURL, fileType: fileType)
        } catch {
            throw SegmentWriterError.writerCreationFailed
        }
        writer.movieTimeScale = 600
        input = AVAssetWriterInput(
            mediaType: kind == .screen ? .video : .audio,
            outputSettings: outputSettings
        )
        input.expectsMediaDataInRealTime = true
        if kind == .screen {
            input.mediaTimeScale = 600
        }
        guard writer.canAdd(input) else {
            writer.cancelWriting()
            throw SegmentWriterError.cannotAddTrack(kind)
        }
        writer.add(input)
    }

    func recordAppend(at timestamp: CMTime) {
        if firstTimestamp == nil {
            firstTimestamp = timestamp
        }
        appendedSampleCount += 1
    }

    func finish() async {
        await withCheckedContinuation { continuation in
            writer.finishWriting {
                continuation.resume()
            }
        }
    }

    func cancel(fileManager: FileManager) {
        writer.cancelWriting()
        try? fileManager.removeItem(at: output.partialURL)
    }
}
