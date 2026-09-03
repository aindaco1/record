import Foundation
import RecordCore

protocol ParakeetModelArchiveDownloading: Sendable {
    func downloadV3Archive(to outputFile: FileHandle) async throws
}

final class XPCParakeetModelArchiveDownloader: ParakeetModelArchiveDownloading,
    @unchecked Sendable
{
    enum ClientError: Error, CustomStringConvertible {
        case unavailable

        var description: String {
            switch self {
            case .unavailable:
                "Record’s protected model downloader is unavailable."
            }
        }
    }

    private final class ReplyGate: @unchecked Sendable {
        private let lock = NSLock()
        private var continuation: CheckedContinuation<Void, Error>?

        init(_ continuation: CheckedContinuation<Void, Error>) {
            self.continuation = continuation
        }

        func resolve(_ result: Result<Void, Error>) {
            lock.lock()
            let pending = continuation
            continuation = nil
            lock.unlock()
            pending?.resume(with: result)
        }
    }

    func downloadV3Archive(to outputFile: FileHandle) async throws {
        let connection = NSXPCConnection(
            serviceName: "com.aindaco.record.model-downloader"
        )
        connection.remoteObjectInterface = NSXPCInterface(
            with: ParakeetModelDownloaderXPCProtocol.self
        )
        connection.resume()
        defer { connection.invalidate() }

        try await withCheckedThrowingContinuation { continuation in
            let gate = ReplyGate(continuation)
            connection.interruptionHandler = {
                gate.resolve(.failure(ClientError.unavailable))
            }
            connection.invalidationHandler = {
                gate.resolve(.failure(ClientError.unavailable))
            }
            guard
                let proxy = connection.remoteObjectProxyWithErrorHandler({ error in
                    gate.resolve(.failure(error))
                }) as? ParakeetModelDownloaderXPCProtocol
            else {
                gate.resolve(.failure(ClientError.unavailable))
                return
            }
            proxy.downloadParakeetV3(to: outputFile) { error in
                if let error {
                    gate.resolve(.failure(error))
                } else {
                    gate.resolve(.success(()))
                }
            }
        }
    }
}

enum ParakeetModelArchiveExtractor {
    static func extract(_ archive: URL, to destination: URL) throws {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        task.arguments = [
            "--norsrc",
            "--noextattr",
            "-x",
            "-k",
            archive.path,
            destination.path,
        ]
        let errorURL = destination.appendingPathComponent(".record-ditto-error")
        guard
            FileManager.default.createFile(
                atPath: errorURL.path,
                contents: nil,
                attributes: [.posixPermissions: 0o600]
            )
        else {
            throw ParakeetModelInstaller.InstallerError.archiveExtractionFailed(
                "Record couldn’t create a private extraction log."
            )
        }
        defer { try? FileManager.default.removeItem(at: errorURL) }
        let errorHandle = try FileHandle(forWritingTo: errorURL)
        defer { try? errorHandle.close() }
        task.standardError = errorHandle
        try task.run()
        task.waitUntilExit()
        try? errorHandle.close()
        guard task.terminationReason == .exit, task.terminationStatus == 0 else {
            let detail = (try? String(contentsOf: errorURL, encoding: .utf8))?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw ParakeetModelInstaller.InstallerError.archiveExtractionFailed(
                detail?.isEmpty == false ? detail! : "The archive could not be expanded."
            )
        }
    }
}
