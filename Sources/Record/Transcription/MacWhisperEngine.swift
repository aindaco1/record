import AVFoundation
import Foundation

/// Optional on-device transcription through MacWhisper's `mw` command-line
/// tool. Sandboxed builds use the user-installed NSUserUnixTask copy because
/// `mw` communicates with MacWhisper over a Unix socket. This is an explicit
/// trust-boundary expansion; the CLI receives exact arguments without shell
/// expansion and never persists history.
actor MacWhisperEngine: TranscriptionEngine {
    enum EngineError: Error, CustomStringConvertible {
        case executableMissing(URL)
        case invalidModel(String)
        case unreadableAudio(URL, Error?)
        case launchFailed(Error)
        case commandFailed(status: Int32, message: String)
        case outputMissing
        case outputInvalid(Error)
        case invalidSegment(startMilliseconds: Int, endMilliseconds: Int)

        var description: String {
            switch self {
            case .executableMissing(let url):
                return "MacWhisper CLI is not executable at \(url.path)"
            case .invalidModel(let model):
                return "invalid MacWhisper model identifier: \(model)"
            case .unreadableAudio(let url, let error):
                return "unreadable or empty audio \(url.lastPathComponent)"
                    + (error.map { ": \($0)" } ?? "")
            case .launchFailed(let error):
                return "MacWhisper CLI failed to launch: \(error)"
            case .commandFailed(let status, let message):
                return "MacWhisper CLI exited \(status)"
                    + (message.isEmpty ? "" : ": \(message)")
            case .outputMissing:
                return "MacWhisper CLI did not produce transcript JSON"
            case .outputInvalid(let error):
                return "MacWhisper returned invalid transcript JSON: \(error)"
            case .invalidSegment(let start, let end):
                return "MacWhisper returned an invalid segment range: \(start)-\(end) ms"
            }
        }
    }

    nonisolated let name = "macwhisper"
    nonisolated let model: String

    private let executable: URL
    private let language: String

    init(executable: URL, model: String, language: String) throws {
        let trimmedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedModel.isEmpty,
            !trimmedModel.hasPrefix("-"),
            !trimmedModel.unicodeScalars.contains(where: {
                CharacterSet.controlCharacters.contains($0)
            })
        else {
            throw EngineError.invalidModel(model)
        }
        self.executable = executable
        self.model = trimmedModel
        self.language = language
    }

    func prepare() async throws {
        guard FileManager.default.isExecutableFile(atPath: executable.path) else {
            throw EngineError.executableMissing(executable)
        }
    }

    func transcribe(_ audio: URL) async throws -> [TranscriptSegment] {
        let audioDuration: TimeInterval
        do {
            let probe = try AVAudioFile(forReading: audio)
            guard probe.length > 0, probe.processingFormat.sampleRate > 0 else {
                throw EngineError.unreadableAudio(audio, nil)
            }
            audioDuration = Double(probe.length) / probe.processingFormat.sampleRate
        } catch let error as EngineError {
            throw error
        } catch {
            throw EngineError.unreadableAudio(audio, error)
        }

        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("record-macwhisper-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: temporaryDirectory,
            withIntermediateDirectories: false
        )
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
        let output = temporaryDirectory.appendingPathComponent("transcript.json")
        let stderr = temporaryDirectory.appendingPathComponent("stderr.log")

        try await run(
            arguments: [
                "transcribe",
                "--model", model,
                "--language", language,
                "--no-speakers",
                "--format", "json",
                "--output", output.path,
                audio.path,
            ],
            stderr: stderr
        )

        guard FileManager.default.fileExists(atPath: output.path) else {
            throw EngineError.outputMissing
        }
        let decoded: Output
        do {
            decoded = try JSONDecoder().decode(Output.self, from: Data(contentsOf: output))
        } catch {
            throw EngineError.outputInvalid(error)
        }

        let segments = try decoded.segments.compactMap { segment -> TranscriptSegment? in
            let text = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            guard segment.start >= 0, segment.end >= segment.start else {
                throw EngineError.invalidSegment(
                    startMilliseconds: segment.start,
                    endMilliseconds: segment.end
                )
            }
            return TranscriptSegment(
                start: TimeInterval(segment.start) / 1_000,
                end: TimeInterval(segment.end) / 1_000,
                text: text
            )
        }
        if !segments.isEmpty { return segments }

        let fallback = decoded.text.trimmingCharacters(in: .whitespacesAndNewlines)
        return fallback.isEmpty
            ? []
            : [TranscriptSegment(start: 0, end: audioDuration, text: fallback)]
    }

    func release() async {}

    private func run(arguments: [String], stderr: URL) async throws {
        FileManager.default.createFile(atPath: stderr.path, contents: nil)
        let errorHandle = try FileHandle(forWritingTo: stderr)
        defer { try? errorHandle.close() }

        if MacWhisperExecutable.isApplicationScript(executable) {
            try await runUserTask(
                arguments: arguments,
                stderr: stderr,
                errorHandle: errorHandle
            )
        } else {
            try await runProcess(arguments: arguments, stderr: stderr, errorHandle: errorHandle)
        }
    }

    private func runUserTask(
        arguments: [String],
        stderr: URL,
        errorHandle: FileHandle
    ) async throws {
        do {
            let task = try NSUserUnixTask(url: executable)
            task.standardError = errorHandle
            try await task.execute(withArguments: arguments)
        } catch {
            let message = readError(stderr)
            throw EngineError.commandFailed(
                status: -1,
                message: message.isEmpty ? String(describing: error) : message
            )
        }
    }

    private func runProcess(
        arguments: [String],
        stderr: URL,
        errorHandle: FileHandle
    ) async throws {
        let task = Process()
        task.executableURL = executable
        task.arguments = arguments
        task.standardInput = FileHandle.nullDevice
        task.standardOutput = FileHandle.nullDevice
        task.standardError = errorHandle
        task.environment = [
            "HOME": FileManager.default.homeDirectoryForCurrentUser.path,
            "LANG": "en_US.UTF-8",
            "PATH": "/usr/bin:/bin",
            "TMPDIR": FileManager.default.temporaryDirectory.path,
        ]

        try await withCheckedThrowingContinuation { continuation in
            task.terminationHandler = { _ in continuation.resume() }
            do {
                try task.run()
            } catch {
                continuation.resume(throwing: EngineError.launchFailed(error))
            }
        }
        guard task.terminationStatus == 0 else {
            throw EngineError.commandFailed(
                status: task.terminationStatus,
                message: readError(stderr)
            )
        }
    }

    private func readError(_ url: URL) -> String {
        let data = (try? Data(contentsOf: url)) ?? Data()
        return
            String(data: data.prefix(4_096), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private struct Output: Decodable {
        struct Segment: Decodable {
            let start: Int
            let end: Int
            let text: String
        }

        let text: String
        let segments: [Segment]
    }
}

enum MacWhisperExecutable {
    static let installedName = "record-macwhisper"

    static var applicationScript: URL? {
        FileManager.default.urls(for: .applicationScriptsDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent(installedName)
    }

    static var isSandboxed: Bool {
        ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil
            || FileManager.default.homeDirectoryForCurrentUser.path.contains(
                "/Library/Containers/com.aindaco.record/Data"
            )
    }

    static func resolve(configuredPath: String?) -> URL? {
        let configured = configuredPath.map { URL(fileURLWithPath: $0) }
        let candidates: [URL]
        if isSandboxed {
            candidates = [applicationScript].compactMap { $0 }
        } else {
            candidates = [
                configured,
                applicationScript,
                URL(fileURLWithPath: "/opt/homebrew/bin/mw"),
                URL(fileURLWithPath: "/Applications/MacWhisper.app/Contents/MacOS/mw"),
            ].compactMap { $0 }
        }
        return
            candidates
            .first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    static func isApplicationScript(_ url: URL) -> Bool {
        guard let directory = applicationScript?.deletingLastPathComponent() else { return false }
        return url.standardizedFileURL.deletingLastPathComponent() == directory.standardizedFileURL
    }
}
