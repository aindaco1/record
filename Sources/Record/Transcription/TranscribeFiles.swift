import AppKit
import ArgumentParser
import Foundation
import RecordCore
import UniformTypeIdentifiers

struct TranscribeFiles: ParsableCommand, Sendable {
    static let configuration = CommandConfiguration(
        commandName: "transcribe",
        abstract:
            "Copy local audio files into sessions and transcribe with the selected local engine.")

    @Argument(help: "Audio files. Originals are kept unchanged.")
    var files: [String] = []

    @Option(
        name: .long, help: "Existing output folder. Defaults to the app’s approved save folder.")
    var output: String?

    @Flag(
        name: .long,
        help: "Choose files and an output folder in native dialogs to grant sandbox access.")
    var authorize = false

    mutating func validate() throws {
        guard authorize || !files.isEmpty else {
            throw ValidationError("Provide audio files or use --authorize.")
        }
        for path in files where path.contains("://") {
            throw ValidationError("Only local file paths are accepted.")
        }
    }

    func run() throws {
        // Resolve native dialogs on the real main thread before dispatchMain
        // transfers queue servicing to libdispatch. MainActor alone is not a
        // main-thread guarantee after that handoff.
        FluidAudioOfflinePolicy.enforce()
        let selection = try MainActor.assumeIsolated { try resolveSelection() }
        Task {
            do { try await transcribe(selection); Self.exit() } catch {
                Self.exit(withError: error)
            }
        }
        dispatchMain()
    }

    private func transcribe(_ selection: Selection) async throws {
        defer {
            selection.files.forEach { $0.stopAccessingSecurityScopedResource() }
            withExtendedLifetime(selection.lease) {}
        }
        let coordinator = TranscriptionCoordinator()
        var failed = false
        for file in selection.files {
            do {
                let directory = try await AudioFileImporter.importInBackground(
                    file, into: selection.lease.url)
                // Print the preserved session even if recognition later fails.
                print(directory.path)
                try await coordinator.transcribeImportedFile(directory)
            } catch {
                failed = true
                let message =
                    (error as? LocalizedError)?.errorDescription ?? String(describing: error)
                FileHandle.standardError.write(Data("\(file.lastPathComponent): \(message)\n".utf8))
            }
        }
        await coordinator.releaseEngine()
        if failed { throw ExitCode.failure }
    }

    private struct Selection: Sendable {
        let files: [URL]
        let lease: ExportDirectoryLease
    }

    @MainActor
    private func resolveSelection() throws -> Selection {
        if authorize {
            let app = NSApplication.shared
            app.setActivationPolicy(.accessory)
            // This command owns a modal loop, not NSApplication.run(). Finish
            // launch so Launch Services and accessibility can reach its panels.
            app.finishLaunching()
            app.activate(ignoringOtherApps: true)
            let input = NSOpenPanel()
            input.title = L10n.text("Import Audio")
            input.message = L10n.text(
                "Choose audio files to copy into Sessions and transcribe locally. Your originals stay in place."
            )
            input.allowsMultipleSelection = true
            input.canChooseDirectories = false
            input.allowedContentTypes = AudioImportPolicy.extensions.compactMap {
                UTType(filenameExtension: $0)
            }
            input.directoryURL = files.first.map {
                URL(fileURLWithPath: $0).deletingLastPathComponent()
            }
            guard input.runModal() == .OK else { throw ExitCode.failure }
            let destination = NSOpenPanel()
            destination.title = L10n.text("Choose Export Folder")
            destination.canChooseFiles = false
            destination.canChooseDirectories = true
            destination.canCreateDirectories = true
            destination.directoryURL = output.map { URL(fileURLWithPath: $0, isDirectory: true) }
            guard destination.runModal() == .OK, let root = destination.url else {
                input.urls.forEach { $0.stopAccessingSecurityScopedResource() }
                throw ExitCode.failure
            }
            return Selection(
                files: input.urls, lease: ExportDirectoryLease(url: root, stopAccessOnRelease: true)
            )
        }
        let lease: ExportDirectoryLease
        if let output {
            lease = ExportDirectoryLease(
                url: URL(fileURLWithPath: output, isDirectory: true), stopAccessOnRelease: false)
        } else if let saved = try ExportDirectoryAccess().restore() {
            lease = saved
        } else {
            throw ValidationError(
                "Choose a save folder in Record, pass --output, or use --authorize.")
        }
        let urls = files.map { URL(fileURLWithPath: $0) }
        guard FileManager.default.isWritableFile(atPath: lease.url.path),
            urls.allSatisfy({ FileManager.default.isReadableFile(atPath: $0.path) })
        else {
            throw ValidationError(
                "Record cannot access these files or the output folder. Use --authorize to grant access in native dialogs."
            )
        }
        return Selection(files: urls, lease: lease)
    }
}
