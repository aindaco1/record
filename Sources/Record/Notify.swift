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

    let recordingsRoot: URL

    init(recordingsRoot: URL) {
        self.recordingsRoot = recordingsRoot.standardizedFileURL
    }

    func token(for directory: URL) -> String? {
        let directory = directory.standardizedFileURL
        if directory == recordingsRoot {
            return Self.recordingsRootToken
        }
        guard directory.deletingLastPathComponent() == recordingsRoot else {
            return nil
        }
        let name = directory.lastPathComponent
        guard Self.isSafeComponent(name) else { return nil }
        return name
    }

    func resolve(_ token: String) -> URL? {
        if token == Self.recordingsRootToken {
            return recordingsRoot.resolvingSymlinksInPath()
        }
        guard Self.isSafeComponent(token) else { return nil }
        let candidate = recordingsRoot.appendingPathComponent(token, isDirectory: true)
            .standardizedFileURL
        guard candidate.deletingLastPathComponent() == recordingsRoot else { return nil }
        let resolvedRoot = recordingsRoot.resolvingSymlinksInPath()
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
    private let directories: NotificationDirectoryReference

    init(
        recordingsRoot: URL,
        center: UNUserNotificationCenter = .current()
    ) {
        self.center = center
        directories = NotificationDirectoryReference(recordingsRoot: recordingsRoot)
        super.init()
        center.delegate = self
    }

    func post(_ notification: RecordNotification) {
        guard let token = directories.token(for: notification.destinationDirectory) else {
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
        let directory = token.flatMap(directories.resolve)
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
