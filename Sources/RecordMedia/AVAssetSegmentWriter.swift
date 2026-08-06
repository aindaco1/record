import AVFoundation
import CoreMedia
import Foundation
import RecordCapture
import RecordCore

public enum SegmentWriterResult: Equatable, Sendable {
    case empty
    case finalized(URL)
}

/// Serial real-time processor for one independently finalized QuickTime
/// segment. Use it behind `BoundedScreenCaptureSink`, then call `finish()` only
/// after the ingress has drained.
public final class AVAssetSegmentWriter: MediaSampleProcessing, @unchecked Sendable {
    public enum State: String, Equatable, Sendable {
        case configured
        case writing
        case finishing
        case completed
        case failed
    }

    public private(set) var state: State = .configured

    private let output: SegmentOutput
    private let fileManager: FileManager
    private let writer: AVAssetWriter
    private let screenInput: AVAssetWriterInput
    private let systemAudioInput: AVAssetWriterInput?
    private let microphoneInput: AVAssetWriterInput?

    private var timeline: CommonMediaTimeline?
    private var result: SegmentWriterResult?
    private var terminalFailure: CaptureFailure?
    private var preservesPartialOnFailure = false
    private var appendedSampleCount = 0

    public init(
        plan: SegmentWriterPlan,
        output: SegmentOutput,
        fileManager: FileManager = .default
    ) throws {
        self.output = output
        self.fileManager = fileManager
        do {
            writer = try AVAssetWriter(outputURL: output.partialURL, fileType: .mov)
        } catch {
            throw SegmentWriterError.writerCreationFailed
        }
        writer.movieTimeScale = 600

        screenInput = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: plan.makeVideoSettings()
        )
        screenInput.expectsMediaDataInRealTime = true
        screenInput.mediaTimeScale = CMTimeScale(plan.framesPerSecond * 10)

        if plan.includesSystemAudio {
            let input = AVAssetWriterInput(
                mediaType: .audio,
                outputSettings: plan.makeAudioSettings()
            )
            input.expectsMediaDataInRealTime = true
            systemAudioInput = input
        } else {
            systemAudioInput = nil
        }

        if plan.includesMicrophone {
            let input = AVAssetWriterInput(
                mediaType: .audio,
                outputSettings: plan.makeAudioSettings()
            )
            input.expectsMediaDataInRealTime = true
            microphoneInput = input
        } else {
            microphoneInput = nil
        }

        try Self.add(screenInput, kind: .screen, to: writer)
        if let systemAudioInput {
            try Self.add(systemAudioInput, kind: .systemAudio, to: writer)
        }
        if let microphoneInput {
            try Self.add(microphoneInput, kind: .microphone, to: writer)
        }
    }

    deinit {
        guard state != .completed, !preservesPartialOnFailure else { return }
        writer.cancelWriting()
        try? fileManager.removeItem(at: output.partialURL)
    }

    public func process(
        _ sample: ScreenCaptureSample
    ) throws -> MediaSampleProcessingResult {
        guard state == .configured || state == .writing else {
            throw SegmentWriterError.invalidState(state)
        }
        guard let input = input(for: sample.kind) else {
            return .dropped(.trackDisabled)
        }

        if state == .configured {
            guard writer.startWriting() else {
                let failure = CaptureFailure(
                    code: .encoderFailed,
                    summary: "hardware encoder failed to start"
                )
                transitionToFailure(failure, removePartial: true)
                throw MediaSampleProcessingFailure(failure)
            }
            writer.startSession(atSourceTime: sample.timestamp.time)
            timeline = try CommonMediaTimeline(anchor: sample.timestamp.time)
            state = .writing
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
            transitionToFailure(failure, removePartial: true)
            throw MediaSampleProcessingFailure(failure)
        }

        guard input.isReadyForMoreMediaData else {
            return .dropped(.writerBackpressure)
        }
        guard input.append(sample.buffer) else {
            let failure = CaptureFailure(
                code: .writerFailed,
                summary: "media segment could not accept a sample"
            )
            transitionToFailure(failure, removePartial: true)
            throw MediaSampleProcessingFailure(failure)
        }
        appendedSampleCount += 1
        return .consumed
    }

    public func finish() async throws -> SegmentWriterResult {
        switch state {
        case .configured:
            writer.cancelWriting()
            try? fileManager.removeItem(at: output.partialURL)
            state = .completed
            result = .empty
            return .empty

        case .writing:
            guard appendedSampleCount > 0 else {
                writer.cancelWriting()
                try? fileManager.removeItem(at: output.partialURL)
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
                    ?? CaptureFailure(code: .writerFailed, summary: "media segment failed")
            )
        }

        screenInput.markAsFinished()
        systemAudioInput?.markAsFinished()
        microphoneInput?.markAsFinished()
        await withCheckedContinuation { continuation in
            writer.finishWriting {
                continuation.resume()
            }
        }

        guard writer.status == .completed else {
            let failure = CaptureFailure(
                code: .writerFailed,
                summary: "media segment could not be finalized"
            )
            transitionToFailure(failure, removePartial: true)
            throw SegmentWriterError.writingFailed(failure)
        }

        do {
            try fileManager.moveItem(at: output.partialURL, to: output.finalURL)
        } catch {
            let failure = CaptureFailure(
                code: .writerFailed,
                summary: "finalized segment could not be promoted"
            )
            transitionToFailure(failure, removePartial: false)
            throw SegmentWriterError.writingFailed(failure)
        }
        let finalized = SegmentWriterResult.finalized(output.finalURL)
        result = finalized
        state = .completed
        return finalized
    }

    private func input(for kind: ScreenCaptureSampleKind) -> AVAssetWriterInput? {
        switch kind {
        case .screen: screenInput
        case .systemAudio: systemAudioInput
        case .microphone: microphoneInput
        }
    }

    private static func add(
        _ input: AVAssetWriterInput,
        kind: ScreenCaptureSampleKind,
        to writer: AVAssetWriter
    ) throws {
        guard writer.canAdd(input) else {
            writer.cancelWriting()
            throw SegmentWriterError.cannotAddTrack(kind)
        }
        writer.add(input)
    }

    private func transitionToFailure(
        _ failure: CaptureFailure,
        removePartial: Bool
    ) {
        state = .failed
        terminalFailure = failure
        preservesPartialOnFailure = !removePartial
        writer.cancelWriting()
        if removePartial {
            try? fileManager.removeItem(at: output.partialURL)
        }
    }
}
