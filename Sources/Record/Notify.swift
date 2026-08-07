import AppKit
import Foundation
import OSLog
@preconcurrency import UserNotifications

struct RecordNotification: Equatable, Sendable {
    let title: String
    let body: String
    let destinationDirectory: URL
}

private enum NotificationUserInfoKey {
    static let directoryToken = "recordDirectoryToken"
}

struct RecordNotificationRequest: Sendable {
    let title: String
    let body: String
    let directoryToken: String
}

protocol RecordNotificationCenterClient: Sendable {
    func authorizationStatus() async -> UNAuthorizationStatus
    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool
    func add(_ request: RecordNotificationRequest) async throws
}

private struct SystemRecordNotificationCenterClient: RecordNotificationCenterClient,
    @unchecked Sendable
{
    let center: UNUserNotificationCenter

    func authorizationStatus() async -> UNAuthorizationStatus {
        await center.notificationSettings().authorizationStatus
    }

    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool {
        try await center.requestAuthorization(options: options)
    }

    func add(_ request: RecordNotificationRequest) async throws {
        let content = UNMutableNotificationContent()
        content.title = request.title
        content.body = request.body
        content.sound = .default
        content.threadIdentifier = "record.recordings"
        content.userInfo = [NotificationUserInfoKey.directoryToken: request.directoryToken]

        try await center.add(
            UNNotificationRequest(
                identifier: UUID().uuidString,
                content: content,
                trigger: nil
            )
        )
    }
}

actor RecordNotificationDelivery {
    private static let logger = Logger(
        subsystem: "com.aindaco.record",
        category: "notifications"
    )

    private let client: any RecordNotificationCenterClient
    private var authorizationRequest: Task<Bool, Error>?

    init(client: any RecordNotificationCenterClient) {
        self.client = client
    }

    @discardableResult
    func prepareAuthorization() async -> Bool {
        do {
            return try await canDeliverNotifications()
        } catch {
            Self.logNotificationFailure(error)
            return false
        }
    }

    func post(_ notification: RecordNotification, directoryToken: String) async {
        guard await prepareAuthorization() else { return }
        do {
            try await client.add(
                RecordNotificationRequest(
                    title: notification.title,
                    body: notification.body,
                    directoryToken: directoryToken
                )
            )
        } catch {
            Self.logNotificationFailure(error)
        }
    }

    private func canDeliverNotifications() async throws -> Bool {
        let status = await client.authorizationStatus()
        Self.logger.info(
            "Notification authorization status: \(status.rawValue, privacy: .public)"
        )
        switch status {
        case .authorized, .provisional, .ephemeral:
            return true
        case .notDetermined:
            if let authorizationRequest {
                return try await authorizationRequest.value
            }
            let request = Task {
                try await client.requestAuthorization(options: [.alert, .sound])
            }
            authorizationRequest = request
            defer { authorizationRequest = nil }
            return try await request.value
        case .denied:
            return false
        @unknown default:
            return false
        }
    }

    private static func logNotificationFailure(_ error: Error) {
        let error = error as NSError
        logger.error(
            "Notification delivery failed: \(error.domain, privacy: .public) \(error.code)"
        )
        FileHandle.standardError.write(
            Data(
                "Record could not post a notification (\(error.domain) \(error.code))\n".utf8
            )
        )
    }
}

/// Stores only a direct child name (or the recordings root marker) in the
/// notification database. Resolution fails closed if the payload is altered.
struct NotificationDirectoryReference: Equatable, Sendable {
    static let recordingsRootToken = "."
    static let exportRootToken = "exports:."
    static let exportPrefix = "exports:"

    let recordingsRoot: URL
    let exportRoot: URL?

    init(recordingsRoot: URL, exportRoot: URL? = nil) {
        self.recordingsRoot = recordingsRoot.standardizedFileURL
        self.exportRoot = exportRoot?.standardizedFileURL
    }

    func token(for directory: URL) -> String? {
        let directory = directory.standardizedFileURL
        if directory == recordingsRoot {
            return Self.recordingsRootToken
        }
        guard directory.deletingLastPathComponent() == recordingsRoot else {
            guard let exportRoot else { return nil }
            if directory == exportRoot {
                return Self.exportRootToken
            }
            guard directory.deletingLastPathComponent() == exportRoot else {
                return nil
            }
            let name = directory.lastPathComponent
            guard Self.isSafeComponent(name) else { return nil }
            return Self.exportPrefix + name
        }
        let name = directory.lastPathComponent
        guard Self.isSafeComponent(name) else { return nil }
        return name
    }

    func resolve(_ token: String) -> URL? {
        if token == Self.exportRootToken {
            return exportRoot?.resolvingSymlinksInPath()
        }
        if token.hasPrefix(Self.exportPrefix) {
            guard let exportRoot else { return nil }
            let component = String(token.dropFirst(Self.exportPrefix.count))
            return Self.resolve(component, under: exportRoot)
        }
        if token == Self.recordingsRootToken {
            return recordingsRoot.resolvingSymlinksInPath()
        }
        return Self.resolve(token, under: recordingsRoot)
    }

    private static func resolve(_ component: String, under root: URL) -> URL? {
        guard isSafeComponent(component) else { return nil }
        let candidate = root.appendingPathComponent(component, isDirectory: true)
            .standardizedFileURL
        guard candidate.deletingLastPathComponent() == root else { return nil }
        let resolvedRoot = root.resolvingSymlinksInPath()
        let resolved = candidate.resolvingSymlinksInPath()
        guard resolved.deletingLastPathComponent() == resolvedRoot else { return nil }
        return resolved
    }

    private static func isSafeComponent(_ value: String) -> Bool {
        !value.isEmpty
            && value != "."
            && value != ".."
            && !value.contains("/")
            && !value.contains(":")
            && !value.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
    }
}

/// App-owned local notifications. Default clicks resolve to a validated
/// recording directory and open it in Finder through NSWorkspace.
final class RecordNotificationCenter: NSObject, UNUserNotificationCenterDelegate,
    @unchecked Sendable
{
    private let delivery: RecordNotificationDelivery
    private let directoryLock = NSLock()
    private var directories: NotificationDirectoryReference

    init(
        recordingsRoot: URL,
        center: UNUserNotificationCenter = .current()
    ) {
        delivery = RecordNotificationDelivery(
            client: SystemRecordNotificationCenterClient(center: center)
        )
        directories = NotificationDirectoryReference(recordingsRoot: recordingsRoot)
        super.init()
        center.delegate = self
    }

    @discardableResult
    func prepareAuthorization() async -> Bool {
        await delivery.prepareAuthorization()
    }

    func updateExportRoot(_ exportRoot: URL?) {
        directoryLock.withLock {
            directories = NotificationDirectoryReference(
                recordingsRoot: directories.recordingsRoot,
                exportRoot: exportRoot
            )
        }
    }

    func post(_ notification: RecordNotification) {
        let token = directoryLock.withLock {
            directories.token(for: notification.destinationDirectory)
        }
        guard let token else {
            FileHandle.standardError.write(
                Data("notification destination was outside recordings root\n".utf8)
            )
            return
        }

        Task { [delivery] in
            await delivery.post(notification, directoryToken: token)
        }
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler:
            @escaping (
                UNNotificationPresentationOptions
            ) -> Void
    ) {
        completionHandler([.banner, .list, .sound])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let token =
            response.notification.request.content.userInfo[
                NotificationUserInfoKey.directoryToken
            ] as? String
        let directory = token.flatMap { token in
            directoryLock.withLock { directories.resolve(token) }
        }
        if let directory {
            Task { @MainActor in
                NSWorkspace.shared.activateFileViewerSelecting([directory])
            }
        }
        completionHandler()
    }
}
