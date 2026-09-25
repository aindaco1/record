import Foundation

// Disposable packaged CLI host: tests the real XPC service without capture or TCC.
@objc protocol RecordReportSenderProbeProtocol {
    func sendReviewedReport(_ bytes: Data, withReply reply: @escaping (Data?, NSError?) -> Void)
}

let syntheticID: UUID?
if CommandLine.arguments.count == 3, CommandLine.arguments[1] == "--send-synthetic",
    let id = UUID(uuidString: CommandLine.arguments[2]) {
    syntheticID = id
} else if CommandLine.arguments.count == 1 {
    syntheticID = nil
} else {
    fputs("usage: probe [--send-synthetic UUID]\n", stderr)
    exit(64)
}

// Fixed synthetic values isolate canaries from real-release crash groups.
struct SyntheticReport: Encodable {
    struct Application: Encodable {
        let architecture = "arm64", version = "0.0.0", build = "99999999", operatingSystem = "15.0.0"
    }
    struct State: Encodable {
        let activity = "idle", screenSource = "mainDisplay", transcription = "disabled"
        let transcriptCleanup = false, modelSetupInProgress = false
        let events = ["launch"]
    }
    struct Crash: Encodable {
        let exception = "EXC_CRASH", signal = "SIGABRT", image = "record"
        let imageOffset = 424242
        let version = "0.0.0", build = "99999999", operatingSystem = "15.0.0"
    }
    let schema = "record-diagnostic-v1", kind = "native_crash"
    let id: String
    let application = Application(), state = State(), crash = Crash()
}
let bytes: Data
if let syntheticID {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    bytes = try encoder.encode(SyntheticReport(id: syntheticID.uuidString.lowercased()))
} else {
    bytes = Data("{\"rawLog\":\"synthetic-private-marker\"}".utf8)
}

guard let serviceName = Bundle.main.object(forInfoDictionaryKey: "RecordReportSenderServiceName") as? String else {
    exit(64)
}
let connection = NSXPCConnection(serviceName: serviceName)
connection.remoteObjectInterface = NSXPCInterface(with: RecordReportSenderProbeProtocol.self)
let completion = DispatchSemaphore(value: 0)
connection.resume()
let proxy = connection.remoteObjectProxyWithErrorHandler { error in
    fputs("Report helper connection failed: \((error as NSError).domain)\n", stderr)
    exit(1)
} as! RecordReportSenderProbeProtocol
proxy.sendReviewedReport(bytes) { data, error in
    if let syntheticID {
        guard error == nil, let data, data.count <= 8192,
            let response = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            response["ok"] as? Bool == true,
            response["reportId"] as? String == syntheticID.uuidString.lowercased(),
            let number = response["issueNumber"] as? Int, (1...Int(Int32.max)).contains(number)
        else {
            fputs("Synthetic report delivery was not confirmed\n", stderr)
            exit(1)
        }
        print(String(decoding: data, as: UTF8.self))
    } else {
        guard data == nil, error?.domain == "RecordReportSender", error?.code == 1 else {
            fputs("Report helper did not reject the invalid projection\n", stderr)
            exit(1)
        }
        print("Packaged report helper rejected private input before transport")
    }
    completion.signal()
}
if completion.wait(timeout: .now() + 30) == .timedOut {
    fputs("Report helper did not reply\n", stderr)
    exit(1)
}
connection.invalidate()
