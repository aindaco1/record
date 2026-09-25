import DustWaveDiagnostics
import Foundation
import RecordCore

/// No URL, path, file descriptor or general request is accepted from the app.
private final class ReportSenderService: NSObject, RecordReportSenderXPCProtocol {
    private final class ReplyBox: @unchecked Sendable {
        let reply: (Data?, NSError?) -> Void
        init(_ reply: @escaping (Data?, NSError?) -> Void) { self.reply = reply }
    }

    func sendReviewedReport(_ bytes: Data, withReply reply: @escaping (Data?, NSError?) -> Void) {
        let box = ReplyBox(reply)
        Task {
            do {
                let report = try RecordDiagnosticReport.reviewed(bytes)
                guard let id = UUID(uuidString: report.id) else {
                    throw ReportDeliveryError.invalidReport
                }
                let receipt = try await ReviewedReportClient().send(
                    bytes, reportID: id,
                    endpoint: URL(string: "https://crash.dustwave.xyz/v1/record/reports")!
                )
                let acknowledgement = try JSONSerialization.data(withJSONObject: [
                    "ok": true, "reportId": report.id, "issueNumber": receipt.issueNumber,
                    "action": receipt.duplicate ? "duplicate" : "created",
                ])
                box.reply(acknowledgement, nil)
            } catch {
                box.reply(nil, NSError(domain: "RecordReportSender", code: 1))
            }
        }
    }
}

private final class ServiceDelegate: NSObject, NSXPCListenerDelegate {
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection)
        -> Bool
    {
        connection.exportedInterface = NSXPCInterface(with: RecordReportSenderXPCProtocol.self)
        connection.exportedObject = ReportSenderService()
        connection.resume()
        return true
    }
}

private let serviceDelegate = ServiceDelegate()
private let listener = NSXPCListener.service()
listener.delegate = serviceDelegate
listener.resume()
RunLoop.current.run()
