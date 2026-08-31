import Foundation

/// Shared metadata checks for local artifacts that must be real files rather
/// than directories or symbolic links. Callers remain responsible for
/// extension, containment, and media-format validation.
public enum LocalFilePolicy {
    public static func regularFileSize(at url: URL) -> UInt64? {
        guard url.isFileURL,
            let values = try? url.resourceValues(
                forKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey]
            ),
            values.isRegularFile == true,
            values.isSymbolicLink != true,
            let fileSize = values.fileSize,
            fileSize >= 0
        else { return nil }

        return UInt64(fileSize)
    }

    public static func isNonemptyRegularFile(_ url: URL) -> Bool {
        guard let byteCount = regularFileSize(at: url) else { return false }
        return byteCount > 0
    }
}
