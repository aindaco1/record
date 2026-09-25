import DustWaveDiagnostics
import Foundation
import RecordCore
import XCTest

final class RecordDiagnosticReportTests: XCTestCase {
    private func sample() throws -> RecordDiagnosticReport {
        let path = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Fixtures/record-diagnostic.json")
        return try JSONDecoder().decode(RecordDiagnosticReport.self, from: Data(contentsOf: path))
    }

    func testGoldenContractAndCanonicalHelperInput() throws {
        let report = try sample()
        let bytes = try report.encoded()
        XCTAssertEqual(try RecordDiagnosticReport.reviewed(bytes).id, report.id)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        object["privatePath"] = "/Users/private/recording.wav"
        let encoder = JSONSerialization.WritingOptions([
            .prettyPrinted, .sortedKeys, .withoutEscapingSlashes,
        ])
        XCTAssertThrowsError(
            try RecordDiagnosticReport.reviewed(
                JSONSerialization.data(withJSONObject: object, options: encoder)))
        XCTAssertThrowsError(try RecordDiagnosticReport.reviewed(Data(repeating: 32, count: 8193)))
    }

    func testRejectsMutablePrivateValuesAndOverlongEvents() throws {
        var r = try sample()
        r.application.build = "private"
        XCTAssertThrowsError(try r.encoded())
        r = try sample(); r.state.events = Array(repeating: .launch, count: 21)
        XCTAssertThrowsError(try r.encoded())
        r = try sample(); r.kind = "native_crash"
        XCTAssertThrowsError(try r.encoded())
        r = try sample(); r.application.architecture = "Private Mac"
        XCTAssertThrowsError(try r.encoded())
    }

    func testCrashProjectionExcludesRawIncidentAndUsesIncidentVersions() throws {
        let header: [String: Any] = [
            "bundleID": "com.aindaco.record", "app_version": "1.4.5", "build_version": "145",
            "privateName": "PRIVATE",
        ]
        let body: [String: Any] = [
            "procName": "record", "exception": ["type": "EXC_CRASH", "signal": "SIGABRT"],
            "osVersion": ["train": "macOS 27.0.0"], "faultingThread": 0,
            "threads": [["frames": [["imageIndex": 0, "imageOffset": 42, "symbol": "PRIVATE"]]]],
            "usedImages": [["name": "record", "path": "/Users/PRIVATE/record"]],
            "procPath": "/Users/PRIVATE/record",
        ]
        var incident = try JSONSerialization.data(withJSONObject: header)
        incident.append(10)
        incident.append(try JSONSerialization.data(withJSONObject: body))
        var r = try sample()
        try r.includeCrash(incident)
        let bytes = try r.encoded()
        XCTAssertEqual(r.application.build, "145")
        XCTAssertEqual(r.crash?.imageOffset, 42)
        XCTAssertFalse(String(decoding: bytes, as: UTF8.self).contains("PRIVATE"))
        XCTAssertEqual(try RecordDiagnosticReport.reviewed(bytes).kind, "native_crash")
        let wrong = String(decoding: incident, as: UTF8.self).replacingOccurrences(
            of: "com.aindaco.record", with: "other.app")
        XCTAssertThrowsError(try r.includeCrash(Data(wrong.utf8)))
        XCTAssertThrowsError(try r.includeCrash(Data(repeating: 32, count: 2_097_153)))
    }

    func testSnapshotBoundsEventsAndSanitizesVersions() throws {
        let state = RecordDiagnosticReport.State(
            activity: .idle, screenSource: .mainDisplay, transcription: .disabled,
            transcriptCleanup: false, modelSetupInProgress: false,
            events: Array(repeating: .launch, count: 100))
        let r = RecordDiagnosticReport(
            version: "private version", build: "debug-name", operatingSystem: "27.0.0", state: state
        )
        XCTAssertEqual(r.state.events.count, 20)
        XCTAssertEqual(r.application.version, "0")
        XCTAssertFalse(String(decoding: try r.encoded(), as: UTF8.self).contains("private"))
    }
}
