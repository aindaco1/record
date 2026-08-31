import AppKit
import Foundation
import RecordCore

enum GifskiHandoff {
    static let bundleIdentifier = "com.sindresorhus.Gifski"

    enum HandoffError: Error, Equatable {
        case appUnavailable
        case invalidVideo
        case launchFailed
    }

    @MainActor static var isAvailable: Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) != nil
    }

    static func validate(
        videoURL: URL,
        fileManager: FileManager = .default
    ) throws {
        guard videoURL.isFileURL,
            videoURL.pathExtension.lowercased() == "mov",
            fileManager.fileExists(atPath: videoURL.path),
            LocalFilePolicy.isNonemptyRegularFile(videoURL)
        else {
            throw HandoffError.invalidVideo
        }
    }

    @MainActor static func open(
        videoURL: URL,
        completion: @escaping @MainActor (Result<Void, HandoffError>) -> Void
    ) throws {
        try validate(videoURL: videoURL)
        guard
            let applicationURL = NSWorkspace.shared.urlForApplication(
                withBundleIdentifier: bundleIdentifier
            )
        else {
            throw HandoffError.appUnavailable
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.open(
            [videoURL],
            withApplicationAt: applicationURL,
            configuration: configuration
        ) { application, error in
            Task { @MainActor in
                completion(
                    error == nil && application != nil ? .success(()) : .failure(.launchFailed))
            }
        }
    }
}
