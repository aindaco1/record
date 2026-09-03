import Foundation
@testable import RecordModelDownload
import RecordCore
import XCTest

final class ParakeetRemoteDownloaderTests: XCTestCase {
    func testCompletionGateResolvesOnlyOnce() {
        let counter = LockedCounter()
        let gate = ParakeetRemoteDownloader.CompletionGate { _ in counter.increment() }

        gate.resolve(nil)
        gate.resolve(ParakeetRemoteDownloader.DownloadError.invalidResponse)

        XCTAssertEqual(counter.value, 1)
    }

    func testInvalidPinnedURLFailsWithoutStartingNetworkWork() throws {
        let descriptor = ParakeetModelDownloadDescriptor(
            assetName: "model.zip",
            downloadURLString: "not a URL",
            byteCount: 1,
            sha256: String(repeating: "0", count: 64)
        )
        let downloader = ParakeetRemoteDownloader(descriptor: descriptor)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "record-remote-downloader-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let outputURL = root.appendingPathComponent("output")
        FileManager.default.createFile(atPath: outputURL.path, contents: nil)
        let output = try FileHandle(forWritingTo: outputURL)
        defer { try? output.close() }
        let completed = expectation(description: "download rejected")

        downloader.download(to: output) { error in
            XCTAssertNotNil(error)
            completed.fulfill()
        }

        wait(for: [completed], timeout: 1)
    }

    func testOnlyTransientConnectionErrorsExposeResumeData() {
        let resumeData = Data("resume".utf8)
        let retryable = NSError(
            domain: NSURLErrorDomain,
            code: NSURLErrorNetworkConnectionLost,
            userInfo: ["NSURLSessionDownloadTaskResumeData": resumeData]
        )
        let offline = NSError(
            domain: NSURLErrorDomain,
            code: NSURLErrorNotConnectedToInternet,
            userInfo: ["NSURLSessionDownloadTaskResumeData": resumeData]
        )
        let unrelated = NSError(
            domain: NSPOSIXErrorDomain,
            code: Int(EIO),
            userInfo: ["NSURLSessionDownloadTaskResumeData": resumeData]
        )

        XCTAssertEqual(ParakeetRemoteDownloader.retryResumeData(for: retryable), resumeData)
        XCTAssertNil(ParakeetRemoteDownloader.retryResumeData(for: offline))
        XCTAssertNil(ParakeetRemoteDownloader.retryResumeData(for: unrelated))
        XCTAssertTrue(ParakeetRemoteDownloader.isRetryableConnectionError(retryable))
        XCTAssertFalse(ParakeetRemoteDownloader.isRetryableConnectionError(offline))
        XCTAssertFalse(ParakeetRemoteDownloader.isRetryableConnectionError(unrelated))
    }

    func testFreshAndResumedDownloadStatusesAreAccepted() {
        XCTAssertTrue(ParakeetRemoteDownloader.isSuccessfulResponseStatus(200))
        XCTAssertTrue(ParakeetRemoteDownloader.isSuccessfulResponseStatus(206))
        XCTAssertFalse(ParakeetRemoteDownloader.isSuccessfulResponseStatus(204))
        XCTAssertFalse(ParakeetRemoteDownloader.isSuccessfulResponseStatus(302))
    }

    func testDownloaderErrorsBridgeWithUserFacingDescriptions() {
        XCTAssertEqual(
            (ParakeetRemoteDownloader.DownloadError.invalidResponse as NSError)
                .localizedDescription,
            "GitHub returned an invalid response for the Parakeet model."
        )
    }
}

private final class LockedCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }

    func increment() {
        lock.lock()
        count += 1
        lock.unlock()
    }
}
