import DustWaveDiagnostics
import Foundation

/// Closed, content-free public projection. Never encode configuration or session objects.
public struct RecordDiagnosticReport: Codable {
    public static let maximumBytes = 8192
    public static let crashImages: Set<String> = [
        "record", "Record", "Sparkle", "AppKit", "SwiftUI", "SwiftUICore",
        "ScreenCaptureKit", "AVFoundation", "CoreMedia", "VideoToolbox",
        "libswiftCore.dylib", "libsystem_kernel.dylib",
    ]

    public enum Activity: String, Codable, Sendable {
        case idle, busy, screenRecording, audioRecording, paused
    }
    public enum Engine: String, Codable, Sendable { case disabled, parakeet, macwhisper }
    public enum Source: String, Codable, Sendable { case mainDisplay, systemPicker, region }
    public enum Event: String, Codable, Sendable {
        case launch, recordingRequested, recordingStopped, pauseResumeRequested
        case screenshotSaved, screenshotFailed, shortcutUnavailable
    }
    public struct State: Codable {
        public var activity: Activity
        public var screenSource: Source
        public var transcription: Engine
        public var transcriptCleanup: Bool
        public var modelSetupInProgress: Bool
        public var events: [Event]

        public init(
            activity: Activity, screenSource: Source, transcription: Engine,
            transcriptCleanup: Bool, modelSetupInProgress: Bool, events: [Event]
        ) {
            self.activity = activity
            self.screenSource = screenSource
            self.transcription = transcription
            self.transcriptCleanup = transcriptCleanup
            self.modelSetupInProgress = modelSetupInProgress
            self.events = Array(events.suffix(20))
        }
    }
    public struct Application: Codable {
        public var version: String
        public var build: String
        public var operatingSystem: String
        public var architecture = "arm64"
    }

    public var schema = "record-diagnostic-v1"
    public var id: String
    public var kind = "current_state"
    public var application: Application
    public var state: State
    public var crash: NativeCrashSummary?

    public init(
        version: String, build: String, operatingSystem: String, state: State,
        id: UUID = UUID()
    ) {
        self.id = id.uuidString.lowercased()
        application = Application(
            version: NativeCrashSummary.numericVersion(version),
            build: NativeCrashSummary.numericVersion(build),
            operatingSystem: NativeCrashSummary.numericVersion(operatingSystem)
        )
        self.state = state
    }

    public mutating func includeCrash(_ data: Data) throws {
        let summary = try NativeCrashSummary.project(
            data, bundleID: "com.aindaco.record", processNames: ["record", "Record"],
            images: Self.crashImages
        )
        crash = summary
        kind = "native_crash"
        application.version = summary.version
        application.build = summary.build
        application.operatingSystem = summary.operatingSystem
    }

    public func encoded() throws -> Data {
        guard schema == "record-diagnostic-v1",
            UUID(uuidString: id)?.uuidString.lowercased() == id,
            ["current_state", "native_crash"].contains(kind),
            application.architecture == "arm64",
            [application.version, application.build, application.operatingSystem]
                .allSatisfy({ NativeCrashSummary.numericVersion($0) == $0 }),
            state.events.count <= 20
        else { throw ReportDeliveryError.invalidReport }
        if kind == "native_crash" {
            guard let crash,
                NativeCrashSummary.exceptions.contains(crash.exception),
                crash.signal.map(NativeCrashSummary.signals.contains) ?? true,
                crash.image.map(Self.crashImages.contains) ?? true,
                crash.imageOffset.map({ (0...1_000_000_000).contains($0) }) ?? true,
                (crash.image == nil) == (crash.imageOffset == nil),
                crash.version == application.version, crash.build == application.build,
                crash.operatingSystem == application.operatingSystem
            else { throw ReportDeliveryError.invalidReport }
        } else if crash != nil {
            throw ReportDeliveryError.invalidReport
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let bytes = try encoder.encode(self)
        guard bytes.count <= Self.maximumBytes else { throw ReportDeliveryError.invalidReport }
        return bytes
    }

    /// Accept only bytes the preview encoder can produce: unknown fields, free-form
    /// additions, nulls and alternate encodings cannot cross the helper boundary.
    public static func reviewed(_ bytes: Data) throws -> Self {
        guard !bytes.isEmpty, bytes.count <= maximumBytes else {
            throw ReportDeliveryError.invalidReport
        }
        let report = try JSONDecoder().decode(Self.self, from: bytes)
        guard try report.encoded() == bytes else { throw ReportDeliveryError.invalidReport }
        return report
    }
}

@objc public protocol RecordReportSenderXPCProtocol {
    func sendReviewedReport(_ bytes: Data, withReply reply: @escaping (Data?, NSError?) -> Void)
}
