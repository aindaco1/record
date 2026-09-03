import Foundation
import RecordCore

public final class ParakeetRemoteDownloader: NSObject, URLSessionTaskDelegate,
    @unchecked Sendable
{
    final class CompletionGate: @unchecked Sendable {
        private let lock = NSLock()
        private var completion: (@Sendable (Error?) -> Void)?

        init(_ completion: @escaping @Sendable (Error?) -> Void) {
            self.completion = completion
        }

        func resolve(_ error: Error?) {
            lock.lock()
            let pending = completion
            completion = nil
            lock.unlock()
            pending?(error)
        }
    }

    public enum DownloadError: Error, LocalizedError, CustomStringConvertible {
        case alreadyDownloading
        case invalidDownloadURL
        case invalidResponse
        case untrustedResponseURL

        public var description: String {
            switch self {
            case .alreadyDownloading:
                "A Parakeet model download is already in progress."
            case .invalidDownloadURL:
                "Record's pinned Parakeet download URL is invalid."
            case .invalidResponse:
                "GitHub returned an invalid response for the Parakeet model."
            case .untrustedResponseURL:
                "The Parakeet model download redirected outside GitHub."
            }
        }

        public var errorDescription: String? { description }
    }

    private let descriptor: ParakeetModelDownloadDescriptor
    private let maximumRetryCount: Int
    private let lock = NSLock()
    private var session: URLSession?
    private var task: URLSessionDownloadTask?
    private var cancellationRequested = false

    public override init() {
        descriptor = .v3
        maximumRetryCount = 3
        super.init()
    }

    init(
        descriptor: ParakeetModelDownloadDescriptor = .v3,
        maximumRetryCount: Int = 3
    ) {
        self.descriptor = descriptor
        self.maximumRetryCount = max(0, maximumRetryCount)
        super.init()
    }

    public func download(
        to outputFile: FileHandle,
        completion: @escaping @Sendable (Error?) -> Void
    ) {
        let completionGate = CompletionGate(completion)
        guard let url = URL(string: descriptor.downloadURLString) else {
            completionGate.resolve(DownloadError.invalidDownloadURL)
            return
        }
        guard descriptor.allowsDownloadURL(url) else {
            completionGate.resolve(DownloadError.untrustedResponseURL)
            return
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieAcceptPolicy = .never
        configuration.httpShouldSetCookies = false
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 900
        configuration.waitsForConnectivity = true
        configuration.urlCache = nil
        let downloadSession = URLSession(
            configuration: configuration,
            delegate: self,
            delegateQueue: nil
        )
        lock.lock()
        guard task == nil, session == nil else {
            lock.unlock()
            downloadSession.invalidateAndCancel()
            completionGate.resolve(DownloadError.alreadyDownloading)
            return
        }
        session = downloadSession
        cancellationRequested = false
        lock.unlock()
        startDownloadTask(
            in: downloadSession,
            url: url,
            resumeData: nil,
            retriesRemaining: maximumRetryCount,
            outputFile: outputFile,
            completion: { error in completionGate.resolve(error) }
        )
    }

    public func cancel() {
        lock.lock()
        let activeTask = task
        cancellationRequested = true
        lock.unlock()
        activeTask?.cancel()
    }

    static func retryResumeData(for error: Error) -> Data? {
        let error = error as NSError
        guard isRetryableConnectionError(error) else { return nil }
        return error.userInfo["NSURLSessionDownloadTaskResumeData"] as? Data
    }

    static func isRetryableConnectionError(_ error: Error) -> Bool {
        let error = error as NSError
        guard error.domain == NSURLErrorDomain else { return false }
        let retryableCodes: Set<Int> = [
            NSURLErrorCannotConnectToHost,
            NSURLErrorNetworkConnectionLost,
            NSURLErrorTimedOut,
        ]
        return retryableCodes.contains(error.code)
    }

    static func isSuccessfulResponseStatus(_ statusCode: Int) -> Bool {
        statusCode == 200 || statusCode == 206
    }

    public func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(
            request.url.map(descriptor.allowsDownloadURL) == true ? request : nil
        )
    }

    private func finishDownload(session completedSession: URLSession) {
        lock.lock()
        if session === completedSession {
            task = nil
            session = nil
            cancellationRequested = false
        }
        lock.unlock()
        completedSession.finishTasksAndInvalidate()
    }

    private func startDownloadTask(
        in downloadSession: URLSession,
        url: URL,
        resumeData: Data?,
        retriesRemaining: Int,
        outputFile: FileHandle,
        completion: @escaping @Sendable (Error?) -> Void
    ) {
        let handler: @Sendable (URL?, URLResponse?, Error?) -> Void = {
            [weak self] temporaryURL, response, error in
            guard let self else {
                completion(CancellationError())
                return
            }
            if let error, retriesRemaining > 0, !self.isCancellationRequested {
                let nextResumeData = Self.retryResumeData(for: error)
                let mayRestart = Self.isRetryableConnectionError(error)
                if nextResumeData != nil || mayRestart {
                    self.startDownloadTask(
                        in: downloadSession,
                        url: url,
                        resumeData: nextResumeData,
                        retriesRemaining: retriesRemaining - 1,
                        outputFile: outputFile,
                        completion: completion
                    )
                    return
                }
            }

            defer { self.finishDownload(session: downloadSession) }
            do {
                if let error { throw error }
                guard
                    let response = response as? HTTPURLResponse,
                    Self.isSuccessfulResponseStatus(response.statusCode),
                    let responseURL = response.url,
                    self.descriptor.allowsDownloadURL(responseURL),
                    let temporaryURL
                else {
                    throw DownloadError.invalidResponse
                }
                try ParakeetModelDownloadVerifier.validate(
                    fileAt: temporaryURL,
                    descriptor: self.descriptor
                )
                try Self.copy(fileAt: temporaryURL, to: outputFile)
                completion(nil)
            } catch {
                completion(error)
            }
        }
        let nextTask =
            if let resumeData {
                downloadSession.downloadTask(
                    withResumeData: resumeData,
                    completionHandler: handler
                )
            } else {
                downloadSession.downloadTask(with: url, completionHandler: handler)
            }

        lock.lock()
        let mayStart = session === downloadSession && !cancellationRequested
        if mayStart { task = nextTask }
        lock.unlock()
        if mayStart {
            nextTask.resume()
        } else {
            nextTask.cancel()
            finishDownload(session: downloadSession)
            completion(CancellationError())
        }
    }

    private var isCancellationRequested: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancellationRequested
    }

    private static func copy(fileAt source: URL, to output: FileHandle) throws {
        let input = try FileHandle(forReadingFrom: source)
        defer { try? input.close() }
        try output.truncate(atOffset: 0)
        while let data = try input.read(upToCount: 1_048_576), !data.isEmpty {
            try output.write(contentsOf: data)
        }
        try output.synchronize()
    }
}
