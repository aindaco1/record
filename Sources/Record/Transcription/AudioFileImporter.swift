import AVFoundation
import Darwin
import Foundation
import RecordCore

/// Copies only explicit local selections. Validation and publication happen on
/// the owned copy; source files are never moved, edited, or passed to an engine.
enum AudioFileImporter {
    static func importInBackground(_ source: URL, into root: URL) async throws -> URL {
        try Task.checkCancellation()
        let worker = Task.detached(priority: .utility) { try importFile(source, into: root) }
        return try await withTaskCancellationHandler {
            try await worker.value
        } onCancel: {
            worker.cancel()
        }
    }

    static func importFile(_ source: URL, into root: URL) throws -> URL {
        let ext = source.pathExtension.lowercased()
        guard source.isFileURL, AudioImportPolicy.extensions.contains(ext) else {
            throw AudioImportPolicy.ImportError.unsupportedFile
        }
        let values = try root.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard values.isDirectory == true, values.isSymbolicLink != true else {
            throw AudioImportPolicy.ImportError.invalidDestination
        }
        let id = UUID()
        let staging = root.appendingPathComponent(
            ".record-import-" + id.uuidString, isDirectory: true)
        let destination = root.appendingPathComponent(
            AudioImportPolicy.sessionName(for: source, id: id), isDirectory: true)
        try FileManager.default.createDirectory(
            at: staging, withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: staging) }
        let filename = "source." + ext
        let copy = staging.appendingPathComponent(filename)
        let bytes = try copySource(source, to: copy)
        let duration = try validateAudio(copy)
        try Task.checkCancellation()
        let now = Date()
        try SessionManifest(
            id: id, state: .finalized, startedAt: now, endedAt: now,
            tracks: [.init(kind: .importedAudio, filename: filename, speaker: "source")],
            importedAudio: .init(
                originalFilename: source.lastPathComponent, byteCount: bytes,
                durationMilliseconds: Int(duration * 1_000))
        ).write(to: staging)
        // A failed/partial import never appears as a transcribable session.
        try FileManager.default.moveItem(at: staging, to: destination)
        return destination
    }

    private static func copySource(_ source: URL, to destination: URL) throws -> UInt64 {
        let descriptor = source.withUnsafeFileSystemRepresentation { path in
            path.map { Darwin.open($0, O_RDONLY | O_NOFOLLOW | O_NONBLOCK) } ?? -1
        }
        guard descriptor >= 0 else { throw AudioImportPolicy.ImportError.unsupportedFile }
        let input = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? input.close() }
        var initial = stat()
        guard fstat(descriptor, &initial) == 0, initial.st_mode & S_IFMT == S_IFREG,
            initial.st_size > 0, UInt64(initial.st_size) <= AudioImportPolicy.maximumBytes
        else { throw AudioImportPolicy.ImportError.unsupportedFile }
        guard
            FileManager.default.createFile(
                atPath: destination.path, contents: nil,
                attributes: [.posixPermissions: 0o600])
        else { throw CocoaError(.fileWriteUnknown) }
        let output = try FileHandle(forWritingTo: destination)
        defer { try? output.close() }
        var copied: UInt64 = 0
        while let data = try input.read(upToCount: 1_024 * 1_024), !data.isEmpty {
            try Task.checkCancellation()
            copied += UInt64(data.count)
            guard copied <= UInt64(initial.st_size) else {
                throw AudioImportPolicy.ImportError.sourceChanged
            }
            try output.write(contentsOf: data)
        }
        var final = stat()
        guard fstat(descriptor, &final) == 0, copied == UInt64(initial.st_size),
            initial.st_size == final.st_size,
            initial.st_mtimespec.tv_sec == final.st_mtimespec.tv_sec,
            initial.st_mtimespec.tv_nsec == final.st_mtimespec.tv_nsec,
            initial.st_ctimespec.tv_sec == final.st_ctimespec.tv_sec,
            initial.st_ctimespec.tv_nsec == final.st_ctimespec.tv_nsec
        else { throw AudioImportPolicy.ImportError.sourceChanged }
        try output.synchronize()
        return copied
    }

    private static func validateAudio(_ url: URL) throws -> Double {
        do {
            let file = try AVAudioFile(forReading: url)
            let format = file.processingFormat
            let duration = Double(file.length) / format.sampleRate
            guard duration.isFinite, duration >= 0.001,
                duration <= AudioImportPolicy.maximumDurationSeconds,
                format.channelCount > 0, format.channelCount <= 32,
                let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 16_384)
            else { throw AudioImportPolicy.ImportError.invalidAudio }
            var frames: AVAudioFramePosition = 0
            while frames < file.length {
                try Task.checkCancellation()
                try file.read(into: buffer)
                guard buffer.frameLength > 0 else {
                    throw AudioImportPolicy.ImportError.invalidAudio
                }
                frames += AVAudioFramePosition(buffer.frameLength)
            }
            return duration
        } catch is CancellationError { throw CancellationError() } catch {
            throw AudioImportPolicy.ImportError.invalidAudio
        }
    }
}
