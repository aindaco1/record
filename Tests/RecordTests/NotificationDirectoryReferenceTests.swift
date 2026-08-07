import Foundation
@testable import Record
@preconcurrency import UserNotifications
import XCTest

final class NotificationDirectoryReferenceTests: XCTestCase {
    func testAuthorizedDeliverySkipsAuthorizationRequest() async {
        let client = FakeNotificationCenterClient(
            authorizationStatus: .authorized,
            grantsAuthorization: false
        )
        let delivery = RecordNotificationDelivery(client: client)

        await delivery.post(
            RecordNotification(
                title: "Transcript ready",
                body: "Saved to Desktop",
                destinationDirectory: URL(fileURLWithPath: "/tmp/session")
            ),
            directoryToken: "exports:session"
        )

        let snapshot = await client.snapshot()
        XCTAssertEqual(snapshot.authorizationRequests, 0)
        XCTAssertEqual(snapshot.titles, ["Transcript ready"])
        XCTAssertEqual(snapshot.directoryTokens, ["exports:session"])
    }

    func testDeliveryRequestsAuthorizationBeforePosting() async {
        let client = FakeNotificationCenterClient(
            authorizationStatus: .notDetermined,
            grantsAuthorization: true
        )
        let delivery = RecordNotificationDelivery(client: client)

        await delivery.post(
            RecordNotification(
                title: "Recording ready",
                body: "Saved to Desktop",
                destinationDirectory: URL(fileURLWithPath: "/tmp/session")
            ),
            directoryToken: "exports:session"
        )

        let snapshot = await client.snapshot()
        XCTAssertEqual(snapshot.authorizationRequests, 1)
        XCTAssertEqual(snapshot.titles, ["Recording ready"])
        XCTAssertEqual(snapshot.directoryTokens, ["exports:session"])
    }

    func testDeniedAuthorizationDoesNotEnqueueNotification() async {
        let client = FakeNotificationCenterClient(
            authorizationStatus: .denied,
            grantsAuthorization: false
        )
        let delivery = RecordNotificationDelivery(client: client)

        await delivery.post(
            RecordNotification(
                title: "Recording ready",
                body: "Saved to Desktop",
                destinationDirectory: URL(fileURLWithPath: "/tmp/session")
            ),
            directoryToken: "exports:session"
        )

        let snapshot = await client.snapshot()
        XCTAssertEqual(snapshot.authorizationRequests, 0)
        XCTAssertTrue(snapshot.titles.isEmpty)
    }

    func testRoundTripsRootAndDirectSessionWithoutPersistingAbsolutePaths() throws {
        let temporaryRoot = try makeTemporaryDirectory()
        let root = temporaryRoot.appendingPathComponent("Recordings", isDirectory: true)
        let session = root.appendingPathComponent("2026.08.06-1230", isDirectory: true)
        try FileManager.default.createDirectory(at: session, withIntermediateDirectories: true)
        let reference = NotificationDirectoryReference(recordingsRoot: root)

        XCTAssertEqual(reference.token(for: root), ".")
        let token = try XCTUnwrap(reference.token(for: session))
        XCTAssertEqual(token, "2026.08.06-1230")
        XCTAssertFalse(token.contains(root.path))
        XCTAssertEqual(reference.resolve(token), session.standardizedFileURL)
    }

    func testRejectsOutsideNestedAndMalformedDestinations() {
        let root = URL(fileURLWithPath: "/tmp/Recordings", isDirectory: true)
        let reference = NotificationDirectoryReference(recordingsRoot: root)

        XCTAssertNil(
            reference.token(
                for: URL(fileURLWithPath: "/tmp/Elsewhere", isDirectory: true)
            )
        )
        XCTAssertNil(
            reference.token(
                for: root.appendingPathComponent("session/private", isDirectory: true)
            )
        )
        for token in ["", "..", "../Elsewhere", "session/private", "session:private"] {
            XCTAssertNil(reference.resolve(token))
        }
    }

    func testRejectsSessionSymlinkThatEscapesRecordingsRoot() throws {
        let temporaryRoot = try makeTemporaryDirectory()
        let recordingsRoot = temporaryRoot.appendingPathComponent(
            "Recordings",
            isDirectory: true
        )
        let outside = temporaryRoot.appendingPathComponent("Outside", isDirectory: true)
        try FileManager.default.createDirectory(
            at: recordingsRoot,
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)

        let link = recordingsRoot.appendingPathComponent("session", isDirectory: true)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside)
        let reference = NotificationDirectoryReference(recordingsRoot: recordingsRoot)

        XCTAssertEqual(reference.token(for: link), "session")
        XCTAssertNil(reference.resolve("session"))
    }

    func testRoundTripsExportedSessionWithoutPersistingItsAbsolutePath() throws {
        let temporaryRoot = try makeTemporaryDirectory()
        let recordingsRoot = temporaryRoot.appendingPathComponent(
            "Recordings",
            isDirectory: true
        )
        let exportRoot = temporaryRoot.appendingPathComponent("Desktop", isDirectory: true)
        let exported = exportRoot.appendingPathComponent("Record Test", isDirectory: true)
        try FileManager.default.createDirectory(
            at: recordingsRoot,
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(at: exported, withIntermediateDirectories: true)
        let reference = NotificationDirectoryReference(
            recordingsRoot: recordingsRoot,
            exportRoot: exportRoot
        )

        let token = try XCTUnwrap(reference.token(for: exported))
        XCTAssertEqual(token, "exports:Record Test")
        XCTAssertFalse(token.contains(temporaryRoot.path))
        XCTAssertEqual(reference.resolve(token), exported.standardizedFileURL)
        XCTAssertEqual(reference.token(for: exportRoot), "exports:.")
        XCTAssertEqual(
            reference.resolve("exports:."),
            exportRoot.standardizedFileURL
        )
    }

    func testRejectsMalformedAndEscapingExportTokens() throws {
        let temporaryRoot = try makeTemporaryDirectory()
        let recordingsRoot = temporaryRoot.appendingPathComponent(
            "Recordings",
            isDirectory: true
        )
        let exportRoot = temporaryRoot.appendingPathComponent("Desktop", isDirectory: true)
        try FileManager.default.createDirectory(
            at: recordingsRoot,
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(at: exportRoot, withIntermediateDirectories: true)
        let reference = NotificationDirectoryReference(
            recordingsRoot: recordingsRoot,
            exportRoot: exportRoot
        )

        for token in ["exports:", "exports:..", "exports:../Outside", "exports:a/b"] {
            XCTAssertNil(reference.resolve(token))
        }
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }
        return directory
    }
}

private actor FakeNotificationCenterClient: RecordNotificationCenterClient {
    struct Snapshot: Sendable {
        let authorizationRequests: Int
        let titles: [String]
        let directoryTokens: [String]
    }

    private let status: UNAuthorizationStatus
    private let grantsAuthorization: Bool
    private var authorizationRequests = 0
    private var titles: [String] = []
    private var directoryTokens: [String] = []

    init(
        authorizationStatus: UNAuthorizationStatus,
        grantsAuthorization: Bool
    ) {
        status = authorizationStatus
        self.grantsAuthorization = grantsAuthorization
    }

    func authorizationStatus() async -> UNAuthorizationStatus {
        status
    }

    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool {
        authorizationRequests += 1
        return grantsAuthorization
    }

    func add(_ request: RecordNotificationRequest) async throws {
        titles.append(request.title)
        directoryTokens.append(request.directoryToken)
    }

    func snapshot() -> Snapshot {
        Snapshot(
            authorizationRequests: authorizationRequests,
            titles: titles,
            directoryTokens: directoryTokens
        )
    }
}
