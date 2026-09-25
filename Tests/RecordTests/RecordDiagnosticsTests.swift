@testable import Record
import DustWaveDiagnostics
import RecordCore
import XCTest

private actor ReportClientStub: RecordReportSending {
    var reports: [Data] = []
    func send(_ bytes: Data) async throws -> ReportReceipt {
        reports.append(bytes)
        if reports.count == 1 { throw ReportDeliveryError.unconfirmed }
        let id = try RecordDiagnosticReport.reviewed(bytes).id
        return try ReportReceipt.decode(
            Data(
                "{\"ok\":true,\"reportId\":\"\(id)\",\"issueNumber\":123,\"action\":\"duplicate\"}"
                    .utf8), reportID: UUID(uuidString: id)!)
    }
}

private actor BlockingReportClient: RecordReportSending {
    private var continuation: CheckedContinuation<ReportReceipt, Error>?
    var calls = 0
    func send(_ bytes: Data) async throws -> ReportReceipt {
        calls += 1
        return try await withCheckedThrowingContinuation { continuation = $0 }
    }
    func fail() {
        continuation?.resume(throwing: ReportDeliveryError.unconfirmed); continuation = nil
    }
}

@MainActor
final class RecordDiagnosticsTests: XCTestCase {
    private func sample() -> RecordDiagnosticReport {
        RecordDiagnosticReport(
            version: "1.4.6", build: "146", operatingSystem: "27.0.0",
            state: .init(
                activity: .idle, screenSource: .mainDisplay, transcription: .parakeet,
                transcriptCleanup: true, modelSetupInProgress: false, events: [.launch]))
    }

    func testExplicitSendRetriesExactReviewedBytesAcrossReopeningAndReleasesUpdateGuard()
        async throws
    {
        let suite = "RecordDiagnosticsTests.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let client = ReportClientStub()
        var busy: [Bool] = []
        let model = RecordDiagnostics(
            defaults: defaults, client: client, setBusy: { busy.append($0) }, snapshot: sample)
        model.prepare()
        let bytes = try XCTUnwrap(model.bytes)
        XCTAssertEqual(model.preview, String(decoding: bytes, as: UTF8.self))
        var sent = await client.reports
        XCTAssertTrue(sent.isEmpty)
        await model.send()
        XCTAssertNil(model.issueNumber)
        XCTAssertTrue(model.status.contains("not confirmed"))
        XCTAssertTrue(model.canSend)
        let reopened = RecordDiagnostics(
            defaults: defaults, client: client, setBusy: { busy.append($0) }, snapshot: sample)
        reopened.prepare()
        XCTAssertEqual(reopened.bytes, bytes)
        await reopened.send()
        XCTAssertEqual(reopened.issueNumber, 123)
        sent = await client.reports
        XCTAssertEqual(sent, [bytes, bytes])
        XCTAssertEqual(busy, [true, false, true, false])
        reopened.refresh()
        XCTAssertNotEqual(reopened.bytes, bytes)
        XCTAssertNil(reopened.issueNumber)
    }

    func testInFlightSendLocksReportAndPreventsDuplicateSubmission() async throws {
        let suite = "RecordDiagnosticsTests.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let client = BlockingReportClient()
        let model = RecordDiagnostics(
            defaults: defaults, client: client, setBusy: { _ in }, snapshot: sample)
        model.prepare()
        let original = model.bytes
        let submission = Task { await model.send() }
        while await client.calls == 0 { await Task.yield() }
        XCTAssertTrue(model.sending)
        XCTAssertFalse(model.canSend)
        model.refresh()
        try model.includeCrash(Data())
        await model.send()
        XCTAssertEqual(model.bytes, original)
        let calls = await client.calls
        XCTAssertEqual(calls, 1)
        await client.fail()
        await submission.value
        XCTAssertTrue(model.canSend)
    }

    func testInvalidSavedReportAndCrashNeverReachTransport() async throws {
        let suite = "RecordDiagnosticsTests.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(Data("{\"rawLog\":\"private\"}".utf8), forKey: "diagnostics.pendingReport.v1")
        let client = ReportClientStub()
        let model = RecordDiagnostics(
            defaults: defaults, client: client, setBusy: { _ in }, snapshot: sample)
        model.prepare()
        let original = model.bytes
        XCTAssertThrowsError(try model.includeCrash(Data("invalid private incident".utf8)))
        XCTAssertEqual(model.bytes, original)
        XCTAssertFalse(model.preview.contains("private"))
        let reports = await client.reports
        XCTAssertTrue(reports.isEmpty)
    }

    func testBoundedCrashReadRejectsSymlinksDirectoriesAndOversizeFiles() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("synthetic.ips")
        try Data("synthetic".utf8).write(to: file)
        XCTAssertEqual(try RecordDiagnostics.readCrashFile(file), Data("synthetic".utf8))
        let link = root.appendingPathComponent("link.ips")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: file)
        XCTAssertThrowsError(try RecordDiagnostics.readCrashFile(link))
        XCTAssertThrowsError(try RecordDiagnostics.readCrashFile(root))
        try Data(repeating: 32, count: 2_097_153).write(to: file)
        XCTAssertThrowsError(try RecordDiagnostics.readCrashFile(file))
    }
}
