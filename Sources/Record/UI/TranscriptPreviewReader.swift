import Darwin
import Foundation
import RecordCore

/// One bounded read policy for both Sessions and the quick-dictation preview.
enum TranscriptPreviewReader {
    static func read(directory: URL, filename: String = "transcript.json") throws
        -> TranscriptDocument
    {
        guard
            ["transcript.json", "transcript.raw.json", TranscriptVocabulary.cleanFilename].contains(
                filename)
        else { throw CocoaError(.fileReadInvalidFileName) }
        let url = directory.appendingPathComponent(filename)
        let fd = open(url.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard fd >= 0 else { throw CocoaError(.fileReadNoSuchFile) }
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        defer { try? handle.close() }
        var info = stat()
        let limit = 8 * 1_024 * 1_024
        guard fstat(fd, &info) == 0, info.st_mode & S_IFMT == S_IFREG,
            info.st_size > 0, info.st_size <= limit
        else { throw CocoaError(.fileReadCorruptFile) }
        let data = try handle.read(upToCount: limit + 1) ?? Data()
        guard data.count <= limit else { throw CocoaError(.fileReadTooLarge) }
        return try JSONDecoder().decode(TranscriptDocument.self, from: data)
    }
}
