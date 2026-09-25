import DustWaveDiagnostics
import Foundation
import RecordCore

protocol RecordReportSending: Sendable {
    func send(_ bytes: Data) async throws -> ReportReceipt
}

struct RecordReportClient: RecordReportSending {
    private final class ReplyGate: @unchecked Sendable {
        private let lock = NSLock()
        private var continuation: CheckedContinuation<Data, Error>?
        init(_ continuation: CheckedContinuation<Data, Error>) { self.continuation = continuation }
        func resolve(_ result: Result<Data, Error>) {
            lock.lock()
            let pending = continuation
            continuation = nil
            lock.unlock()
            pending?.resume(with: result)
        }
    }

    func send(_ bytes: Data) async throws -> ReportReceipt {
        let report = try RecordDiagnosticReport.reviewed(bytes)
        guard let id = UUID(uuidString: report.id) else { throw ReportDeliveryError.invalidReport }
        let connection = NSXPCConnection(serviceName: "com.aindaco.record.report-sender")
        connection.remoteObjectInterface = NSXPCInterface(with: RecordReportSenderXPCProtocol.self)
        connection.resume()
        defer { connection.invalidate() }
        let response: Data = try await withCheckedThrowingContinuation { continuation in
            let gate = ReplyGate(continuation)
            connection.interruptionHandler = {
                gate.resolve(.failure(ReportDeliveryError.unconfirmed))
            }
            connection.invalidationHandler = {
                gate.resolve(.failure(ReportDeliveryError.unconfirmed))
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + 30) {
                gate.resolve(.failure(ReportDeliveryError.unconfirmed))
            }
            guard
                let proxy = connection.remoteObjectProxyWithErrorHandler({ _ in
                    gate.resolve(.failure(ReportDeliveryError.unconfirmed))
                }) as? RecordReportSenderXPCProtocol
            else {
                gate.resolve(.failure(ReportDeliveryError.unconfirmed))
                return
            }
            proxy.sendReviewedReport(bytes) { data, error in
                if error == nil, let data {
                    gate.resolve(.success(data))
                } else {
                    gate.resolve(.failure(ReportDeliveryError.unconfirmed))
                }
            }
        }
        return try ReportReceipt.decode(response, reportID: id)
    }
}
