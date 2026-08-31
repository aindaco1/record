import AVFoundation
@testable import Record
import RecordCore
import XCTest

final class SessionMediaInspectorTests: XCTestCase {
    func testRecognizesPlayableEmptyAndCorruptCAF() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "SessionMediaInspectorTests-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let valid = directory.appendingPathComponent("valid.caf")
        let empty = directory.appendingPathComponent("empty.caf")
        let corrupt = directory.appendingPathComponent("corrupt.caf")
        let format = try XCTUnwrap(
            AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: 48_000,
                channels: 1,
                interleaved: false
            )
        )
        let file = try AVAudioFile(
            forWriting: valid,
            settings: format.settings,
            commonFormat: format.commonFormat,
            interleaved: format.isInterleaved
        )
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 128))
        buffer.frameLength = 128
        try file.write(from: buffer)
        try Data().write(to: empty)
        try Data("not a media container".utf8).write(to: corrupt)

        XCTAssertEqual(try SessionMediaInspector.inspect(valid), .playable)
        XCTAssertEqual(try SessionMediaInspector.inspect(empty), .empty)
        XCTAssertEqual(try SessionMediaInspector.inspect(corrupt), .corrupt)

        let link = directory.appendingPathComponent("linked.caf")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: valid)
        XCTAssertThrowsError(try SessionMediaInspector.inspect(link)) { error in
            XCTAssertEqual(error as? SessionMediaInspector.InspectionError, .unsafeFile)
        }
    }
}
