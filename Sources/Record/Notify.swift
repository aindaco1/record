import AppKit
import Foundation
@preconcurrency import UserNotifications

struct RecordNotification: Equatable, Sendable {
    let title: String
    let body: String
    let destinationDirectory: URL
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
    private enum UserInfoKey {
        static let directoryToken = "recordDirectoryToken"
    }

    private let center: UNUserNotificationCenter
    private let directoryLock = NSLock()
    private var directories: NotificationDirectoryReference

    init(
        recordingsRoot: URL,
        center: UNUserNotificationCenter = .current()
    ) {
        self.center = center
        directories = NotificationDirectoryReference(recordingsRoot: recordingsRoot)
        super.init()
        center.delegate = self
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

        center.getNotificationSettings { [weak self] settings in
            guard let self else { return }
            switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral:
                self.enqueue(notification, directoryToken: token)
            case .notDetermined:
                self.center.requestAuthorization(options: [.alert, .sound]) {
                    [weak self] granted, error in
                    if granted {
                        self?.enqueue(notification, directoryToken: token)
                    } else if error != nil {
                        Self.logNotificationFailure()
                    }
                }
            case .denied:
                break
            @unknown default:
                break
            }
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
                UserInfoKey.directoryToken
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

    private func enqueue(_ notification: RecordNotification, directoryToken: String) {
        let content = UNMutableNotificationContent()
        content.title = notification.title
        content.body = notification.body
        content.sound = .default
        content.threadIdentifier = "record.recordings"
        content.userInfo = [UserInfoKey.directoryToken: directoryToken]

        center.add(
            UNNotificationRequest(
                identifier: UUID().uuidString,
                content: content,
                trigger: nil
            )
        ) { error in
            if error != nil {
                Self.logNotificationFailure()
            }
        }
    }

    private static func logNotificationFailure() {
        FileHandle.standardError.write(Data("Record could not post a notification\n".utf8))
    }
}
