import AppIntents
import Darwin
import Foundation
@testable import Record
import RecordCore
import XCTest

final class RecordingAutomationTests: XCTestCase, @unchecked Sendable {
    private func mailbox() throws -> RecordingControlMailbox {
        try RecordingControlMailbox(
            directory: FileManager.default.temporaryDirectory
                .appendingPathComponent("record-control-test-\(UUID().uuidString)"))
    }

    func testOnlyOneClientOrServerOwnsTheMailboxAndStaleEndpointCannotReceiveCommands() throws {
        let box = try mailbox()
        defer { try? FileManager.default.removeItem(at: box.directory) }
        let ownership = try box.acquire("server")
        XCTAssertThrowsError(try box.acquire("server"))
        let client = try box.acquire("client")
        XCTAssertThrowsError(try box.send(action: .status, mode: nil))
        withExtendedLifetime((ownership, client)) {}
    }

    func testStaleEndpointWithoutServerLockIsUnavailable() throws {
        let box = try mailbox()
        defer { try? FileManager.default.removeItem(at: box.directory) }
        try box.write(
            RecordingControlMailbox.Endpoint(instance: UUID()),
            name: "endpoint.json")
        XCTAssertThrowsError(try box.send(action: .start, mode: .dictation)) { error in
            guard case RecordingControlMailbox.MailboxError.unavailable = error else {
                return XCTFail("A stale endpoint must not accept commands")
            }
        }
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: box.directory.appendingPathComponent("request.json").path))
    }

    func testClientReusesTheServersExistingPrivateDirectory() throws {
        let server = try mailbox()
        defer { try? FileManager.default.removeItem(at: server.directory) }
        let client = try RecordingControlMailbox(directory: server.directory)
        XCTAssertEqual(client.directory, server.directory)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755], ofItemAtPath: server.directory.path)
        XCTAssertThrowsError(try RecordingControlMailbox(directory: server.directory))
    }

    func testMailboxRejectsOversizedSymlinkAndFIFOInputsWithoutBlocking() throws {
        let box = try mailbox()
        defer { try? FileManager.default.removeItem(at: box.directory) }
        let request = box.directory.appendingPathComponent("request.json")
        try Data(repeating: 32, count: RecordingControlMailbox.byteLimit + 1).write(to: request)
        XCTAssertThrowsError(try box.read(RecordingControl.Request.self, name: "request.json"))
        try FileManager.default.removeItem(at: request)
        try FileManager.default.createSymbolicLink(at: request, withDestinationURL: box.directory)
        XCTAssertThrowsError(try box.read(RecordingControl.Request.self, name: "request.json"))
        try FileManager.default.removeItem(at: request)
        XCTAssertEqual(mkfifo(request.path, 0o600), 0)
        XCTAssertThrowsError(try box.read(RecordingControl.Request.self, name: "request.json"))
    }

    @MainActor
    func testRelaunchHandsOwnershipToReplacementAndInvalidatesOldRequests() throws {
        let box = try mailbox()
        defer { try? FileManager.default.removeItem(at: box.directory) }
        let original = try RecordingControlServer(mailbox: box)
        try original.start { .init(id: $0.id, snapshot: .init(phase: .idle)) }
        let old = try box.read(RecordingControlMailbox.Endpoint.self, name: "endpoint.json")
        XCTAssertThrowsError(try RecordingControlServer(mailbox: box))
        original.suspend()
        let replacement = try RecordingControlServer(mailbox: box)
        try replacement.start { .init(id: $0.id, snapshot: .init(phase: .idle)) }
        let new = try box.read(RecordingControlMailbox.Endpoint.self, name: "endpoint.json")
        XCTAssertNotEqual(old.instance, new.instance)
        XCTAssertThrowsError(try original.resume())
        replacement.suspend()
        XCTAssertNoThrow(try original.resume())
        XCTAssertNotEqual(
            old.instance,
            try box.read(RecordingControlMailbox.Endpoint.self, name: "endpoint.json").instance)
        withExtendedLifetime(original) {}
    }

    @MainActor
    func testRunningServerHandlesOneMatchingRequestAndIgnoresStaleResponse() async throws {
        let box = try mailbox()
        defer { try? FileManager.default.removeItem(at: box.directory) }
        let server = try RecordingControlServer(mailbox: box)
        var calls = 0
        try server.start { request in
            calls += 1
            return .init(id: request.id, snapshot: .init(phase: .paused, mode: .screen))
        }
        try box.write(
            RecordingControl.Response(id: UUID(), snapshot: .init(phase: .idle)),
            name: "response.json")
        let response = try await Task.detached { try box.send(action: .status, mode: nil) }.value
        XCTAssertEqual(response.snapshot, .init(phase: .paused, mode: .screen))
        XCTAssertNil(response.failure)
        XCTAssertEqual(calls, 1)
        withExtendedLifetime(server) {}
    }

    func testCLIRequiresExplicitStartModeAndRejectsModesForOtherCommands() throws {
        for mode in RecordingControl.Mode.allCases {
            let command = try ControlRecording.parse(["start", "--mode", mode.rawValue, "--json"])
            XCTAssertEqual(command.mode, mode)
            XCTAssertTrue(command.json)
        }
        XCTAssertThrowsError(try ControlRecording.parse(["start"]))
        XCTAssertThrowsError(try ControlRecording.parse(["toggle"]))
        XCTAssertThrowsError(try ControlRecording.parse(["start", "--mode", "camera"]))
        for action in ["stop", "pause", "resume", "status"] {
            XCTAssertNoThrow(try ControlRecording.parse([action]))
            XCTAssertThrowsError(try ControlRecording.parse([action, "--mode", "audio"]))
        }
    }

    @MainActor
    func testShortcutsUseSharedHandlerAndReturnOnlyState() async throws {
        defer { RecordingIntentBridge.handler = nil }
        var actions: [RecordingControl.Action] = []
        RecordingIntentBridge.handler = { request in
            actions.append(request.action)
            if request.action == .start { XCTAssertEqual(request.mode, .dictation) }
            return .init(id: request.id, snapshot: .init(phase: .recording, mode: .dictation))
        }
        let start = StartRecordingIntent()
        start.mode = .dictation
        let result = try await start.perform()
        XCTAssertEqual(result.value, "Recording")
        _ = try await StopRecordingIntent().perform()
        _ = try await PauseRecordingIntent().perform()
        _ = try await ResumeRecordingIntent().perform()
        _ = try await RecordingStatusIntent().perform()
        XCTAssertEqual(actions, [.start, .stop, .pause, .resume, .status])
    }
}
