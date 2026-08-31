import AudioToolbox
import AVFoundation
import Foundation
@testable import Record
import RecordCore
import XCTest

final class SessionAudioFinalizerTests: XCTestCase {
    func testCanonicalOutputLayoutRemainsAudioOnly() {
        XCTAssertEqual(PCM24WaveAudioFinalizer.outputFilename(for: .microphone), "mic.wav")
        XCTAssertEqual(PCM24WaveAudioFinalizer.outputFilename(for: .systemAudio), "system.wav")
        XCTAssertNil(PCM24WaveAudioFinalizer.outputFilename(for: .screen))
        XCTAssertNil(PCM24WaveAudioFinalizer.outputFilename(for: .camera))
    }

    func testFinalizesIndependentCAFTracksAs24BitPCMWaveFiles() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let microphone = directory.appendingPathComponent("mic.caf")
        let system = directory.appendingPathComponent("system.caf")
        try writeAAC(to: microphone, channels: 1)
        try writeAAC(to: system, channels: 2)
        let sourceSizes = try [microphone, system].map(fileSize)

        let outputs = try PCM24WaveAudioFinalizer().finalize([
            .init(kind: .microphone, url: microphone),
            .init(kind: .systemAudio, url: system),
        ])

        XCTAssertEqual(outputs.map(\.url.lastPathComponent), ["mic.wav", "system.wav"])
        XCTAssertEqual(try [microphone, system].map(fileSize), sourceSizes)
        try assertWave(outputs[0].url, channels: 1)
        try assertWave(outputs[1].url, channels: 2)
        XCTAssertFalse(
            try FileManager.default.contentsOfDirectory(atPath: directory.path)
                .contains(where: { $0.contains("partial") })
        )
    }

    func testConversionFailurePreservesEverySourceAndPublishesNoWaveFiles() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let microphone = directory.appendingPathComponent("mic.caf")
        let system = directory.appendingPathComponent("system.caf")
        try writeAAC(to: microphone, channels: 1)
        try Data("not audio".utf8).write(to: system)

        XCTAssertThrowsError(
            try PCM24WaveAudioFinalizer().finalize([
                .init(kind: .microphone, url: microphone),
                .init(kind: .systemAudio, url: system),
            ])
        ) { error in
            XCTAssertEqual(
                error as? PCM24WaveAudioFinalizer.FinalizationError,
                .conversionFailed(.systemAudio)
            )
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: microphone.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: system.path))
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: directory.appendingPathComponent("mic.wav").path
            )
        )
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: directory.appendingPathComponent("system.wav").path
            )
        )
        XCTAssertFalse(
            try FileManager.default.contentsOfDirectory(atPath: directory.path)
                .contains(where: { $0.contains("partial") })
        )
    }

    private func makeDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "record-wave-finalizer-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func writeAAC(to url: URL, channels: AVAudioChannelCount) throws {
        let format = try XCTUnwrap(
            AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: 48_000,
                channels: channels,
                interleaved: false
            )
        )
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 48_000,
            AVNumberOfChannelsKey: Int(channels),
            AVEncoderBitRateKey: 192_000,
        ]
        let file = try AVAudioFile(
            forWriting: url,
            settings: settings,
            commonFormat: format.commonFormat,
            interleaved: format.isInterleaved
        )
        let buffer = try XCTUnwrap(
            AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4_800)
        )
        buffer.frameLength = buffer.frameCapacity
        try file.write(from: buffer)
    }

    private func assertWave(_ url: URL, channels: AVAudioChannelCount) throws {
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        XCTAssertGreaterThan(data.count, 12)
        XCTAssertEqual(String(decoding: data[0..<4], as: UTF8.self), "RIFF")
        XCTAssertEqual(String(decoding: data[8..<12], as: UTF8.self), "WAVE")

        let file = try AVAudioFile(forReading: url)
        let stream = file.fileFormat.streamDescription.pointee
        XCTAssertEqual(stream.mFormatID, kAudioFormatLinearPCM)
        XCTAssertEqual(stream.mBitsPerChannel, UInt32(PCM24WaveAudioFinalizer.bitDepth))
        XCTAssertEqual(file.fileFormat.channelCount, channels)
        XCTAssertEqual(file.fileFormat.sampleRate, 48_000)
        XCTAssertGreaterThan(file.length, 0)
    }

    private func fileSize(_ url: URL) throws -> Int64 {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return try XCTUnwrap((attributes[.size] as? NSNumber)?.int64Value)
    }
}
