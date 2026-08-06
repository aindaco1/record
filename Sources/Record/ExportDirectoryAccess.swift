import AppKit
import Darwin
import Foundation
import RecordCore

/// Owns Record's persistent, user-approved access to the folder for finished
/// exports. Raw crash-recovery sessions remain in the private recordings root;
/// only derived, user-visible files belong here.
@MainActor
final class ExportDirectoryAccess {
    enum AccessError: Error, CustomStringConvertible {
        case resolvedLocationUnavailable(URL)
        case securityScopeDenied(URL)

        var description: String {
            switch self {
            case .resolvedLocationUnavailable(let url):
                return "the saved export folder is unavailable: \(url.path)"
            case .securityScopeDenied(let url):
                return "Record could not restore access to the export folder: \(url.path)"
            }
        }
    }

    static let bookmarkKey = "exportDirectorySecurityScopedBookmark"

    let suggestedDirectory: URL

    private let defaults: UserDefaults

    init(
        defaults: UserDefaults = .standard,
        userHome: URL = ExportDirectoryAccess.loginHomeDirectory()
    ) {
        self.defaults = defaults
        suggestedDirectory = RecordPaths.defaultExportsDirectory(home: userHome)
    }

    /// Resolve the persisted bookmark and hold its security scope until the
    /// returned lease is released.
    func restore() throws -> ExportDirectoryLease? {
        guard let bookmark = defaults.data(forKey: Self.bookmarkKey) else { return nil }

        var isStale = false
        let url = try URL(
            resolvingBookmarkData: bookmark,
            options: [.withSecurityScope, .withoutUI],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ).standardizedFileURL
        try validateDirectory(url)

        guard url.startAccessingSecurityScopedResource() else {
            throw AccessError.securityScopeDenied(url)
        }

        do {
            if isStale {
                try storeBookmark(for: url)
            }
            return ExportDirectoryLease(url: url, stopAccessOnRelease: true)
        } catch {
            url.stopAccessingSecurityScopedResource()
            throw error
        }
    }

    /// Ask the user for an export folder. The first presentation defaults to
    /// the real Desktop rather than the app container's Desktop symlink.
    func choose() throws -> ExportDirectoryLease? {
        let panel = NSOpenPanel()
        panel.title = "Choose Export Folder"
        panel.message = "Finished Record videos will be saved in this folder."
        panel.prompt = "Choose"
        panel.directoryURL = suggestedDirectory
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.resolvesAliases = true

        guard panel.runModal() == .OK, let selected = panel.url?.standardizedFileURL else {
            return nil
        }
        try validateDirectory(selected)
        try storeBookmark(for: selected)

        // URLs returned by NSOpenPanel already carry an active implicit
        // security scope. Balance it when this lease is released.
        return ExportDirectoryLease(url: selected, stopAccessOnRelease: true)
    }

    func forgetStoredSelection() {
        defaults.removeObject(forKey: Self.bookmarkKey)
    }

    private func storeBookmark(for url: URL) throws {
        let bookmark = try url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        defaults.set(bookmark, forKey: Self.bookmarkKey)
    }

    private func validateDirectory(_ url: URL) throws {
        var isDirectory = ObjCBool(false)
        guard
            FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
            isDirectory.boolValue
        else {
            throw AccessError.resolvedLocationUnavailable(url)
        }
    }

    private static func loginHomeDirectory() -> URL {
        guard let entry = getpwuid(getuid()), let rawHome = entry.pointee.pw_dir else {
            return FileManager.default.homeDirectoryForCurrentUser
        }
        return URL(fileURLWithPath: String(cString: rawHome), isDirectory: true)
    }
}

/// Keeps one security-scoped directory grant balanced for its full lifetime.
final class ExportDirectoryLease {
    let url: URL

    private let stopAccessOnRelease: Bool

    init(url: URL, stopAccessOnRelease: Bool) {
        self.url = url
        self.stopAccessOnRelease = stopAccessOnRelease
    }

    deinit {
        if stopAccessOnRelease {
            url.stopAccessingSecurityScopedResource()
        }
    }
}
