import Foundation

// Disposable packaged CLI host: tests the real XPC service without capture or TCC.
@objc protocol RecordReportSenderProbeProtocol {
    func sendReviewedReport(_ bytes: Data, withReply reply: @escaping (Data?, NSError?) -> Void)
}

let connection = NSXPCConnection(serviceName: "com.aindaco.record.report-sender")
connection.remoteObjectInterface = NSXPCInterface(with: RecordReportSenderProbeProtocol.self)
let completion = DispatchSemaphore(value: 0)
connection.resume()
let proxy = connection.remoteObjectProxyWithErrorHandler { error in
    fputs("Report helper connection failed: \((error as NSError).domain)\n", stderr)
    exit(1)
} as! RecordReportSenderProbeProtocol
// No valid report is sent and no network request is authorized by this smoke.
proxy.sendReviewedReport(Data("{\"rawLog\":\"synthetic-private-marker\"}".utf8)) { data, error in
    guard data == nil, error?.domain == "RecordReportSender", error?.code == 1 else {
        fputs("Report helper did not reject the invalid projection\n", stderr)
        exit(1)
    }
    print("Packaged report helper rejected private input before transport")
    completion.signal()
}
if completion.wait(timeout: .now() + 15) == .timedOut {
    fputs("Report helper did not reply\n", stderr)
    exit(1)
}
connection.invalidate()
