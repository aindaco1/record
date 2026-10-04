import Foundation
import RecordCore
import RecordModelDownload

private final class ModelDownloaderService: NSObject, ParakeetModelDownloaderXPCProtocol,
    @unchecked Sendable
{
    private let downloader = ParakeetRemoteDownloader()
    private let connection: NSXPCConnection
    init(connection: NSXPCConnection) { self.connection = connection }

    private final class ReplyBox: @unchecked Sendable {
        let reply: (NSError?) -> Void

        init(_ reply: @escaping (NSError?) -> Void) {
            self.reply = reply
        }
    }

    func downloadParakeetV3(
        to outputFile: FileHandle,
        withReply reply: @escaping (NSError?) -> Void
    ) {
        let replyBox = ReplyBox(reply)
        downloader.download(
            to: outputFile,
            progress: { [weak self] bytes in
                (self?.connection.remoteObjectProxy as? ParakeetModelDownloadProgressXPCProtocol)?
                    .receivedBytes(bytes)
            }
        ) { error in
            replyBox.reply(error as NSError?)
        }
    }

    func cancelDownload() {
        downloader.cancel()
    }
}

private final class ServiceDelegate: NSObject, NSXPCListenerDelegate {
    func listener(
        _ listener: NSXPCListener,
        shouldAcceptNewConnection connection: NSXPCConnection
    ) -> Bool {
        connection.exportedInterface = NSXPCInterface(
            with: ParakeetModelDownloaderXPCProtocol.self
        )
        connection.remoteObjectInterface = NSXPCInterface(
            with: ParakeetModelDownloadProgressXPCProtocol.self)
        let service = ModelDownloaderService(connection: connection)
        connection.exportedObject = service
        connection.invalidationHandler = { [weak connection, service] in
            service.cancelDownload()
            connection?.exportedObject = nil
            connection?.invalidationHandler = nil
        }
        connection.resume()
        return true
    }
}

private let serviceDelegate = ServiceDelegate()
private let listener = NSXPCListener.service()
listener.delegate = serviceDelegate
listener.resume()
RunLoop.current.run()
