import AudioToolbox
import AVFoundation
import Foundation
@testable import Record
import RecordCore
import XCTest

final class AudioSessionInspectorTests: XCTestCase {
    func testInspectAcceptsCompleteFinalizedAudioSession() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }

        let inspection = try AudioSessionInspector.inspect(
            sessionDirectory: fixture.directory
        )

        XCTAssertEqual(inspection.startedAt, fixture.startedAt)
        XCTAssertEqual(inspection.endedAt, fixture.endedAt)
        XCTAssertEqual(inspection.tracks.map(\.kind), [.microphone, .systemAudio])
        XCTAssertTrue(inspection.tracks.allSatisfy { $0.byteCount > 0 })
        XCTAssertTrue(inspection.tracks.allSatisfy { $0.durationSeconds > 0 })
        XCTAssertTrue(inspection.tracks.allSatisfy { $0.bitDepth == 24 })
    }

    func testInspectRejectsUnfinishedSession() throws {
        let fixture = try makeFixture(state: .recording, endedAt: nil)
        defer { try? FileManager.default.removeItem(at: fixture.directory) }

        XCTAssertThrowsError(
            try AudioSessionInspector.inspect(sessionDirectory: fixture.directory)
        ) { error in
            XCTAssertEqual(
                String(describing: error),
                "session is not finalized: recording"
            )
        }
    }

    func testInspectRejectsNegativeSynchronizationOffset() throws {
        let fixture = try makeFixture(systemOffset: -1)
        defer { try? FileManager.default.removeItem(at: fixture.directory) }

        XCTAssertThrowsError(
            try AudioSessionInspector.inspect(sessionDirectory: fixture.directory)
        ) { error in
            XCTAssertEqual(
                String(describing: error),
                "negative system_audio start offset: -1 ms"
            )
        }
    }

    func testInspectRejectsMissingMediaFile() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        try FileManager.default.removeItem(
            at: fixture.directory.appendingPathComponent("system.wav")
        )

        XCTAssertThrowsError(
            try AudioSessionInspector.inspect(sessionDirectory: fixture.directory)
        ) { error in
            XCTAssertEqual(
                String(describing: error),
                "missing or empty audio track: system.wav"
            )
        }
    }

    func testInspectRejectsSymlinkedMediaFile() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let system = fixture.directory.appendingPathComponent("system.wav")
        let outside = fixture.directory.deletingLastPathComponent().appendingPathComponent(
            "record-inspector-outside-\(UUID().uuidString).wav"
        )
        defer { try? FileManager.default.removeItem(at: outside) }
        try FileManager.default.moveItem(at: system, to: outside)
        try FileManager.default.createSymbolicLink(at: system, withDestinationURL: outside)

        XCTAssertThrowsError(
            try AudioSessionInspector.inspect(sessionDirectory: fixture.directory)
        ) { error in
            XCTAssertEqual(
                String(describing: error),
                "missing or empty audio track: system.wav"
            )
        }
    }

    func testInspectRejectsWaveWithWrongPCMDepth() throws {
        let fixture = try makeFixture(bitDepth: 16)
        defer { try? FileManager.default.removeItem(at: fixture.directory) }

        XCTAssertThrowsError(
            try AudioSessionInspector.inspect(sessionDirectory: fixture.directory)
        ) { error in
            XCTAssertEqual(
                String(describing: error),
                "audio track is not a 24-bit PCM WAV file: mic.wav"
            )
        }
    }

    func testInspectRejectsUnsafeTrackFilename() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        var manifest = try SessionManifest.read(from: fixture.directory)
        manifest.tracks[0].filename = "../mic.wav"
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(manifest).write(
            to: fixture.directory.appendingPathComponent("session.json"),
            options: .atomic
        )

        XCTAssertThrowsError(
            try AudioSessionInspector.inspect(sessionDirectory: fixture.directory)
        ) { error in
            XCTAssertEqual(
                String(describing: error),
                "session contains an unsafe track filename: ../mic.wav"
            )
        }
    }

    private func makeFixture(
        state: SessionManifest.State = .finalized,
        endedAt: Date? = Date(timeIntervalSince1970: 2),
        systemOffset: Int = 3,
        bitDepth: Int = 24
    ) throws -> (directory: URL, startedAt: Date, endedAt: Date) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("record-inspector-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let startedAt = Date(timeIntervalSince1970: 1)
        let resolvedEnd = endedAt ?? Date(timeIntervalSince1970: 2)
        let tracks: [SessionManifest.Track] = [
            .init(kind: .microphone, filename: "mic.wav", speaker: "me"),
            .init(
                kind: .systemAudio,
                filename: "system.wav",
                speaker: "them",
                startOffsetMilliseconds: systemOffset
            ),
        ]
        let manifest = SessionManifest(
            state: state,
            startedAt: startedAt,
            endedAt: endedAt,
            tracks: tracks
        )
        try manifest.write(to: directory)
        try writeAudio(to: directory.appendingPathComponent("mic.wav"), bitDepth: bitDepth)
        try writeAudio(to: directory.appendingPathComponent("system.wav"), bitDepth: bitDepth)
        return (directory, startedAt, resolvedEnd)
    }

    private func writeAudio(to url: URL, bitDepth: Int) throws {
        let format = try XCTUnwrap(
            AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: 16_000,
                channels: 1,
                interleaved: false
            )
        )
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: format.sampleRate,
            AVNumberOfChannelsKey: Int(format.channelCount),
            AVLinearPCMBitDepthKey: bitDepth,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ]
        let file = try AVAudioFile(
            forWriting: url,
            settings: settings,
            commonFormat: format.commonFormat,
            interleaved: format.isInterleaved
        )
        let buffer = try XCTUnwrap(
            AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1_600)
        )
        buffer.frameLength = 1_600
        try file.write(from: buffer)
    }
}
