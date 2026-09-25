import AppKit
import Combine
import Darwin
import DustWaveDiagnostics
import RecordCore
import SwiftUI
import UniformTypeIdentifiers

/// Paper's reviewed-report workflow, with delivery confined to Record's XPC helper.
@MainActor
final class RecordDiagnostics: ObservableObject {
    private static let pendingKey = "diagnostics.pendingReport.v1"
    @Published private(set) var preview = ""
    @Published private(set) var sending = false
    @Published private(set) var status = "Review the report before sending."
    @Published private(set) var issueNumber: Int?
    private(set) var bytes: Data?
    private let snapshot: () -> RecordDiagnosticReport
    private let defaults: UserDefaults
    private let client: any RecordReportSending
    private let setBusy: (Bool) -> Void

    var canSend: Bool { bytes != nil && !sending }

    init(
        defaults: UserDefaults = .standard, client: any RecordReportSending = RecordReportClient(),
        setBusy: @escaping (Bool) -> Void, snapshot: @escaping () -> RecordDiagnosticReport
    ) {
        self.defaults = defaults
        self.client = client
        self.setBusy = setBusy
        self.snapshot = snapshot
    }

    func prepare() {
        guard !sending, bytes == nil else { return }
        if let saved = defaults.data(forKey: Self.pendingKey),
            let report = try? RecordDiagnosticReport.reviewed(saved)
        {
            setReport(report)
        } else {
            refresh()
        }
    }

    func refresh() {
        guard !sending else { return }
        setReport(snapshot())
    }

    private func setReport(_ report: RecordDiagnosticReport) {
        do {
            let data = try report.encoded()
            bytes = data
            preview = String(decoding: data, as: UTF8.self)
            defaults.set(data, forKey: Self.pendingKey)
            issueNumber = nil
            status = "Review the report before sending."
        } catch {
            bytes = nil
            preview = ""
            issueNumber = nil
            defaults.removeObject(forKey: Self.pendingKey)
            status = "Could not prepare the report. Refresh to try again."
        }
    }

    func includeCrash(_ data: Data) throws {
        guard !sending else { return }
        var report = snapshot()
        try report.includeCrash(data)
        setReport(report)
        status = "Crash summary ready for review. The raw file stays on your Mac."
    }

    func importCrash(window: NSWindow?) {
        guard !sending, let window else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "ips") ?? .json]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.message =
            "Choose a Record .ips crash report up to 2 MB. Only the filtered summary can be sent."
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let self, let url = panel.url else { return }
            do {
                guard url.pathExtension.lowercased() == "ips" else {
                    throw ReportDeliveryError.invalidReport
                }
                try self.includeCrash(Self.readCrashFile(url))
            } catch {
                self.status =
                    "Choose a valid Record .ips crash report no larger than 2 MB. The preview is unchanged."
            }
        }
    }

    /// Bound the actual read and reject nonregular files without blocking on a FIFO.
    static func readCrashFile(_ url: URL) throws -> Data {
        let limit = 2_097_152
        guard url.isFileURL else { throw ReportDeliveryError.invalidReport }
        let descriptor = open(url.path, O_RDONLY | O_NONBLOCK | O_CLOEXEC | O_NOFOLLOW)
        guard descriptor >= 0 else { throw ReportDeliveryError.invalidReport }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? handle.close() }
        var info = stat()
        guard fstat(descriptor, &info) == 0,
            info.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG), info.st_size <= limit
        else { throw ReportDeliveryError.invalidReport }
        var data = Data()
        while data.count <= limit {
            let chunk = try handle.read(upToCount: min(65_536, limit + 1 - data.count)) ?? Data()
            if chunk.isEmpty { break }
            data.append(chunk)
        }
        guard data.count <= limit else { throw ReportDeliveryError.invalidReport }
        return data
    }

    func export(window: NSWindow?) {
        guard !sending, let bytes, let window else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "Record-diagnostic.json"
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try bytes.write(to: url, options: .atomic)
                self?.status = "Report saved locally."
            } catch { self?.status = "Could not save the report. Choose another location." }
        }
    }

    func send() async {
        guard canSend, let bytes else { return }
        sending = true
        issueNumber = nil
        setBusy(true)
        status = "Sending the reviewed report…"
        defer { sending = false; setBusy(false) }
        do {
            let receipt = try await client.send(bytes)
            issueNumber = receipt.issueNumber
            status =
                receipt.duplicate
                ? "This report was already received. Its count is unchanged."
                : "Report received. Matching reports share the same issue."
        } catch {
            status =
                "Delivery was not confirmed. Retry sends this same report without counting it twice."
        }
    }

    func openIssue() {
        guard let issueNumber, (1...Int(Int32.max)).contains(issueNumber) else { return }
        var url = URLComponents()
        url.scheme = "https"
        url.host = "github.com"
        url.path = "/aindaco1/record/issues/\(issueNumber)"
        if let url = url.url { NSWorkspace.shared.open(url) }
    }
}

struct RecordDiagnosticsView: View {
    @ObservedObject var model: RecordDiagnostics
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Help & diagnostics").font(.title2)
            Text(
                "Review a filtered report, save it locally, or send it to Record’s public GitHub issues. Matching reports are grouped together."
            )
            .fixedSize(horizontal: false, vertical: true)
            Text(
                "Includes app/system versions, broad capture settings, recent event categories and an optional crash summary. Excludes media, transcripts, names, paths, clipboard content and raw logs. Use private security reporting for vulnerabilities."
            )
            .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            ScrollView {
                Text(model.preview).font(.system(.caption, design: .monospaced)).textSelection(
                    .enabled
                )
                .frame(maxWidth: .infinity, alignment: .leading).padding(12)
            }
            .frame(height: 260).background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
            .accessibilityLabel("Report preview")
            Text(model.status).font(.callout).fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("record.reportStatus")
            if model.issueNumber != nil { Button("View GitHub issue") { model.openIssue() } }
            HStack(spacing: 8) {
                Group {
                    Button("Refresh") { model.refresh() }
                    Button("Import crash log…") { model.importCrash(window: NSApp.keyWindow) }
                    Button("Save report…") { model.export(window: NSApp.keyWindow) }.disabled(
                        model.bytes == nil)
                }.disabled(model.sending)
                Spacer(minLength: 16)
                Button("Send to public GitHub issues") { Task { await model.send() } }
                    .disabled(!model.canSend).buttonStyle(.borderedProminent)
            }.controlSize(.regular)
        }.padding(24).frame(width: 640).onAppear { model.prepare() }
    }
}

@MainActor
final class DiagnosticsWindowController: NSWindowController {
    init(model: RecordDiagnostics) {
        let window = NSWindow(
            contentViewController: NSHostingController(
                rootView: RecordDiagnosticsView(model: model)))
        window.title = "Record — Help & diagnostics"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        super.init(window: window)
    }
    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }
    func show() {
        NSApp.activate(ignoringOtherApps: true)
        window?.center()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }
}
