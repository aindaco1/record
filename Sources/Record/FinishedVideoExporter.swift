import Foundation

enum FinishedVideoExporter {
    enum ExportError: Error, Equatable {
        case invalidSource
        case destinationUnavailable
        case invalidName
    }

    static func export(
        sourceURL: URL,
        to directory: URL,
        preferredBaseName: String,
        fileManager: FileManager = .default
    ) throws -> URL {
        var isDirectory = ObjCBool(false)
        guard sourceURL.isFileURL,
            sourceURL.pathExtension.lowercased() == "mov",
            fileManager.fileExists(atPath: sourceURL.path),
            ((try? sourceURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) > 0
        else {
            throw ExportError.invalidSource
        }
        guard directory.isFileURL,
            fileManager.fileExists(atPath: directory.path, isDirectory: &isDirectory),
            isDirectory.boolValue
        else {
            throw ExportError.destinationUnavailable
        }

        guard !preferredBaseName.isEmpty,
            preferredBaseName.count <= 120,
            preferredBaseName
                == preferredBaseName.trimmingCharacters(
                    in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "."))
                ),
            preferredBaseName.rangeOfCharacter(from: .controlCharacters) == nil,
            preferredBaseName != ".",
            preferredBaseName != "..",
            !preferredBaseName.contains("/"),
            !preferredBaseName.contains(":"),
            URL(fileURLWithPath: preferredBaseName).lastPathComponent == preferredBaseName
        else {
            throw ExportError.invalidName
        }

        let baseName = preferredBaseName
        let finalURL = availableURL(baseName: baseName, in: directory, fileManager: fileManager)
        let partialURL = directory.appendingPathComponent(
            ".\(baseName).\(UUID().uuidString).partial.mov",
            isDirectory: false
        )
        defer { try? fileManager.removeItem(at: partialURL) }

        try fileManager.copyItem(at: sourceURL, to: partialURL)
        try fileManager.moveItem(at: partialURL, to: finalURL)
        return finalURL
    }

    private static func availableURL(
        baseName: String,
        in directory: URL,
        fileManager: FileManager
    ) -> URL {
        var suffix = 1
        while true {
            let name = suffix == 1 ? baseName : "\(baseName)-\(suffix)"
            let candidate = directory.appendingPathComponent(name).appendingPathExtension("mov")
            if !fileManager.fileExists(atPath: candidate.path) {
                return candidate
            }
            suffix += 1
        }
    }
}
