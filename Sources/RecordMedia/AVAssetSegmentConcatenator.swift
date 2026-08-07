@preconcurrency import AVFoundation
import CoreMedia
import Foundation
import RecordCapture

public struct CaptureSegmentArtifactSet: Equatable, Sendable {
    public let index: Int
    public let artifacts: FinalizedSegmentArtifacts

    public init(index: Int, artifacts: FinalizedSegmentArtifacts) {
        self.index = index
        self.artifacts = artifacts
    }
}

/// Joins compatible immutable segments with AVFoundation's passthrough preset.
/// Input media is never removed or rewritten; canonical outputs are promoted
/// only after every composition has finished successfully.
public struct AVAssetSegmentConcatenator: Sendable {
    public enum ConcatenationError: Error, Equatable, Sendable {
        case noSegments
        case invalidSegmentOrder
        case incompatibleTracks
        case invalidMedia(ScreenCaptureSampleKind)
        case cannotCreateComposition(ScreenCaptureSampleKind)
        case insertionFailed(ScreenCaptureSampleKind, segment: Int)
        case cannotCreateExporter(ScreenCaptureSampleKind)
        case unsupportedPassthrough(ScreenCaptureSampleKind)
        case exportFailed(ScreenCaptureSampleKind)
        case audioReaderFailed(ScreenCaptureSampleKind)
        case audioAppendFailed(ScreenCaptureSampleKind)
        case audioFinishFailed(ScreenCaptureSampleKind)
        case audioTimingFailed(ScreenCaptureSampleKind)
        case audioRetimeFailed(ScreenCaptureSampleKind)
        case promotionFailed
    }

    public init() {}

    public func concatenate(
        _ segments: [CaptureSegmentArtifactSet],
        to finalURLs: [ScreenCaptureSampleKind: URL],
        fileManager: FileManager = .default
    ) async throws -> FinalizedSegmentArtifacts {
        guard !segments.isEmpty else { throw ConcatenationError.noSegments }
        guard segments.map(\.index) == Array(1...segments.count) else {
            throw ConcatenationError.invalidSegmentOrder
        }
        let expectedKinds = Set(segments[0].artifacts.files.keys)
        guard !expectedKinds.isEmpty,
            expectedKinds.contains(.screen),
            Set(finalURLs.keys) == expectedKinds,
            segments.allSatisfy({ Set($0.artifacts.files.keys) == expectedKinds })
        else {
            throw ConcatenationError.incompatibleTracks
        }

        let output = try SegmentOutputSet(
            finalURLs: finalURLs,
            fileManager: fileManager
        )
        if segments.count == 1 {
            try copySingleSegment(
                segments[0].artifacts,
                to: output,
                fileManager: fileManager
            )
            return FinalizedSegmentArtifacts(
                files: output.outputs.mapValues(\.finalURL),
                startOffsetMilliseconds: segments[0].artifacts.startOffsetMilliseconds
            )
        }

        let loaded = try await load(segments, fileManager: fileManager)
        let earliestStarts = earliestTrackStarts(in: loaded, kinds: expectedKinds)
        for kind in ScreenCaptureSampleKind.allCases where expectedKinds.contains(kind) {
            guard let destination = output[kind] else {
                throw ConcatenationError.incompatibleTracks
            }
            do {
                try await export(
                    kind: kind,
                    segments: loaded,
                    earliestStart: earliestStarts[kind] ?? .zero,
                    to: destination
                )
            } catch let error as ConcatenationError {
                throw error
            } catch {
                throw ConcatenationError.exportFailed(kind)
            }
        }
        try promote(output, fileManager: fileManager)
        return FinalizedSegmentArtifacts(
            files: output.outputs.mapValues(\.finalURL),
            startOffsetMilliseconds: earliestStarts.mapValues(Self.milliseconds)
        )
    }

    private struct LoadedTrack {
        // AVAssetTrack does not guarantee it keeps its parent URL asset alive.
        let asset: AVURLAsset
        let track: AVAssetTrack
        let timeRange: CMTimeRange
        let offset: CMTime
        let formatDescription: CMFormatDescription
    }

    private struct LoadedSegment {
        let tracks: [ScreenCaptureSampleKind: LoadedTrack]
        let duration: CMTime
        let timelineStart: CMTime
    }

    private func load(
        _ segments: [CaptureSegmentArtifactSet],
        fileManager: FileManager
    ) async throws -> [LoadedSegment] {
        var timelineStart = CMTime.zero
        var result: [LoadedSegment] = []
        for segment in segments {
            var tracks: [ScreenCaptureSampleKind: LoadedTrack] = [:]
            var segmentDuration = CMTime.zero
            for kind in ScreenCaptureSampleKind.allCases {
                guard let url = segment.artifacts[kind] else { continue }
                guard Self.isNonemptyRegularFile(url, fileManager: fileManager) else {
                    throw ConcatenationError.invalidMedia(kind)
                }
                let asset = AVURLAsset(url: url)
                let mediaType: AVMediaType = kind == .screen ? .video : .audio
                let assetTracks = try await asset.loadTracks(withMediaType: mediaType)
                guard assetTracks.count == 1 else {
                    throw ConcatenationError.invalidMedia(kind)
                }
                let track = assetTracks[0]
                let timeRange = try await track.load(.timeRange)
                let formatDescriptions = try await track.load(.formatDescriptions)
                guard timeRange.duration.isNumeric,
                    CMTimeCompare(timeRange.duration, .zero) > 0,
                    let formatDescription = formatDescriptions.first
                else {
                    throw ConcatenationError.invalidMedia(kind)
                }
                let offset = CMTime(
                    value: CMTimeValue(
                        max(0, segment.artifacts.startOffsetMilliseconds[kind] ?? 0)
                    ),
                    timescale: 1_000
                )
                tracks[kind] = LoadedTrack(
                    asset: asset,
                    track: track,
                    timeRange: timeRange,
                    offset: offset,
                    formatDescription: formatDescription
                )
                segmentDuration = CMTimeMaximum(
                    segmentDuration,
                    CMTimeAdd(offset, timeRange.duration)
                )
            }
            guard !tracks.isEmpty, CMTimeCompare(segmentDuration, .zero) > 0 else {
                throw ConcatenationError.incompatibleTracks
            }
            result.append(
                LoadedSegment(
                    tracks: tracks,
                    duration: segmentDuration,
                    timelineStart: timelineStart
                )
            )
            timelineStart = CMTimeAdd(timelineStart, segmentDuration)
        }
        return result
    }

    private func earliestTrackStarts(
        in segments: [LoadedSegment],
        kinds: Set<ScreenCaptureSampleKind>
    ) -> [ScreenCaptureSampleKind: CMTime] {
        Dictionary(
            uniqueKeysWithValues: kinds.compactMap { kind in
                let starts = segments.compactMap { segment in
                    segment.tracks[kind].map {
                        CMTimeAdd(segment.timelineStart, $0.offset)
                    }
                }
                guard let first = starts.min(by: { CMTimeCompare($0, $1) < 0 }) else {
                    return nil
                }
                return (kind, first)
            }
        )
    }

    private func export(
        kind: ScreenCaptureSampleKind,
        segments: [LoadedSegment],
        earliestStart: CMTime,
        to output: SegmentOutput
    ) async throws {
        if kind != .screen {
            try await exportAudioPassthrough(
                kind: kind,
                segments: segments,
                earliestStart: earliestStart,
                to: output
            )
            return
        }
        let composition = AVMutableComposition()
        let mediaType: AVMediaType = kind == .screen ? .video : .audio
        guard
            let compositionTrack = composition.addMutableTrack(
                withMediaType: mediaType,
                preferredTrackID: kCMPersistentTrackID_Invalid
            )
        else {
            throw ConcatenationError.cannotCreateComposition(kind)
        }
        if kind == .screen, let firstTrack = segments.first?.tracks[kind]?.track {
            compositionTrack.preferredTransform = try await firstTrack.load(.preferredTransform)
        }
        for (segmentOffset, segment) in segments.enumerated() {
            guard let source = segment.tracks[kind] else {
                throw ConcatenationError.incompatibleTracks
            }
            let absoluteStart = CMTimeAdd(segment.timelineStart, source.offset)
            do {
                try compositionTrack.insertTimeRange(
                    source.timeRange,
                    of: source.track,
                    at: CMTimeSubtract(absoluteStart, earliestStart)
                )
            } catch {
                throw ConcatenationError.insertionFailed(kind, segment: segmentOffset + 1)
            }
        }
        guard
            let exporter = AVAssetExportSession(
                asset: composition,
                presetName: AVAssetExportPresetPassthrough
            )
        else {
            throw ConcatenationError.cannotCreateExporter(kind)
        }
        let fileType: AVFileType = kind == .screen ? .mov : .caf
        let supportedTypes = await AVAssetExportSession.compatibility(
            ofExportPreset: AVAssetExportPresetPassthrough,
            with: composition,
            outputFileType: fileType
        )
        guard supportedTypes else {
            throw ConcatenationError.unsupportedPassthrough(kind)
        }
        exporter.timeRange = CMTimeRange(start: .zero, duration: composition.duration)
        do {
            try await exporter.export(to: output.partialURL, as: fileType)
        } catch {
            throw ConcatenationError.exportFailed(kind)
        }
    }

    /// AVAssetExportSession does not support CAF passthrough. Read and append
    /// the existing AAC packets with shifted timestamps instead; nil output
    /// settings instruct AVAssetWriter to remux rather than encode.
    private func exportAudioPassthrough(
        kind: ScreenCaptureSampleKind,
        segments: [LoadedSegment],
        earliestStart: CMTime,
        to output: SegmentOutput
    ) async throws {
        guard let first = segments.first?.tracks[kind],
            segments.allSatisfy({ segment in
                guard let track = segment.tracks[kind] else { return false }
                return CMFormatDescriptionEqual(
                    first.formatDescription,
                    otherFormatDescription: track.formatDescription
                )
            })
        else {
            throw ConcatenationError.incompatibleTracks
        }

        let writer: AVAssetWriter
        do {
            writer = try AVAssetWriter(outputURL: output.partialURL, fileType: .caf)
        } catch {
            throw ConcatenationError.cannotCreateExporter(kind)
        }
        let input = AVAssetWriterInput(
            mediaType: .audio,
            outputSettings: nil,
            sourceFormatHint: first.formatDescription
        )
        guard writer.canAdd(input) else {
            throw ConcatenationError.unsupportedPassthrough(kind)
        }
        writer.add(input)
        guard writer.startWriting() else {
            throw ConcatenationError.exportFailed(kind)
        }
        writer.startSession(atSourceTime: .zero)

        do {
            for segment in segments {
                guard let source = segment.tracks[kind] else {
                    throw ConcatenationError.incompatibleTracks
                }
                let reader = try AVAssetReader(asset: source.asset)
                reader.timeRange = source.timeRange
                let readerOutput = AVAssetReaderTrackOutput(
                    track: source.track,
                    outputSettings: nil
                )
                readerOutput.alwaysCopiesSampleData = false
                guard reader.canAdd(readerOutput) else {
                    throw ConcatenationError.unsupportedPassthrough(kind)
                }
                reader.add(readerOutput)
                guard reader.startReading() else {
                    throw ConcatenationError.audioReaderFailed(kind)
                }

                let targetStart = CMTimeSubtract(
                    CMTimeAdd(segment.timelineStart, source.offset),
                    earliestStart
                )
                var sourceStart: CMTime?
                while let sample = readerOutput.copyNextSampleBuffer() {
                    guard CMSampleBufferGetNumSamples(sample) > 0 else { continue }
                    let presentationTime = CMSampleBufferGetPresentationTimeStamp(sample)
                    if sourceStart == nil { sourceStart = presentationTime }
                    let shifted = try Self.copy(
                        sample,
                        shiftingBy: CMTimeSubtract(targetStart, sourceStart ?? presentationTime),
                        kind: kind
                    )
                    while !input.isReadyForMoreMediaData {
                        guard writer.status == .writing else {
                            throw ConcatenationError.exportFailed(kind)
                        }
                        // AVAssetWriter can apply sustained backpressure while
                        // flushing packets. A bounded suspension avoids burning
                        // a core without materially delaying the offline remux.
                        try await Task.sleep(for: .milliseconds(1))
                    }
                    guard input.append(shifted) else {
                        throw ConcatenationError.audioAppendFailed(kind)
                    }
                }
                guard reader.status == .completed else {
                    throw ConcatenationError.audioReaderFailed(kind)
                }
            }
            input.markAsFinished()
            await withCheckedContinuation { continuation in
                writer.finishWriting { continuation.resume() }
            }
            guard writer.status == .completed else {
                throw ConcatenationError.audioFinishFailed(kind)
            }
        } catch let error as ConcatenationError {
            writer.cancelWriting()
            throw error
        } catch {
            writer.cancelWriting()
            throw ConcatenationError.exportFailed(kind)
        }
    }

    private func copySingleSegment(
        _ artifacts: FinalizedSegmentArtifacts,
        to output: SegmentOutputSet,
        fileManager: FileManager
    ) throws {
        for kind in ScreenCaptureSampleKind.allCases {
            guard let source = artifacts[kind], let destination = output[kind] else { continue }
            guard Self.isNonemptyRegularFile(source, fileManager: fileManager) else {
                throw ConcatenationError.invalidMedia(kind)
            }
            try fileManager.copyItem(at: source, to: destination.partialURL)
        }
        try promote(output, fileManager: fileManager)
    }

    private func promote(
        _ output: SegmentOutputSet,
        fileManager: FileManager
    ) throws {
        do {
            for kind in ScreenCaptureSampleKind.allCases {
                guard let file = output[kind] else { continue }
                try fileManager.moveItem(at: file.partialURL, to: file.finalURL)
            }
        } catch {
            throw ConcatenationError.promotionFailed
        }
    }

    private static func milliseconds(_ time: CMTime) -> Int {
        guard time.isNumeric else { return 0 }
        return max(0, Int((CMTimeGetSeconds(time) * 1_000).rounded()))
    }

    private static func copy(
        _ sample: CMSampleBuffer,
        shiftingBy shift: CMTime,
        kind: ScreenCaptureSampleKind
    ) throws -> CMSampleBuffer {
        var count = 0
        _ = CMSampleBufferGetSampleTimingInfoArray(
            sample,
            entryCount: 0,
            arrayToFill: nil,
            entriesNeededOut: &count
        )
        guard count > 0 else {
            throw ConcatenationError.audioTimingFailed(kind)
        }
        var timing = Array(
            repeating: CMSampleTimingInfo(
                duration: .invalid,
                presentationTimeStamp: .invalid,
                decodeTimeStamp: .invalid
            ),
            count: count
        )
        let timingStatus = CMSampleBufferGetSampleTimingInfoArray(
            sample,
            entryCount: count,
            arrayToFill: &timing,
            entriesNeededOut: &count
        )
        guard timingStatus == noErr else {
            throw ConcatenationError.audioTimingFailed(kind)
        }
        for index in timing.indices {
            if timing[index].presentationTimeStamp.isValid {
                timing[index].presentationTimeStamp = CMTimeAdd(
                    timing[index].presentationTimeStamp,
                    shift
                )
            }
            if timing[index].decodeTimeStamp.isValid {
                timing[index].decodeTimeStamp = CMTimeAdd(
                    timing[index].decodeTimeStamp,
                    shift
                )
            }
        }
        var shifted: CMSampleBuffer?
        let copyStatus = CMSampleBufferCreateCopyWithNewTiming(
            allocator: kCFAllocatorDefault,
            sampleBuffer: sample,
            sampleTimingEntryCount: timing.count,
            sampleTimingArray: &timing,
            sampleBufferOut: &shifted
        )
        guard copyStatus == noErr, let shifted else {
            throw ConcatenationError.audioRetimeFailed(kind)
        }
        return shifted
    }

    private static func isNonemptyRegularFile(
        _ url: URL,
        fileManager: FileManager
    ) -> Bool {
        guard url.isFileURL,
            let values = try? url.resourceValues(
                forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]
            )
        else { return false }
        return values.isRegularFile == true
            && values.isSymbolicLink != true
            && (values.fileSize ?? 0) > 0
    }
}
