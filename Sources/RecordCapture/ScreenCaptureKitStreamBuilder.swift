import CoreMedia
import Dispatch
import Foundation
import RecordCore
@preconcurrency import ScreenCaptureKit

public struct ScreenCaptureKitStreamBuilder: Sendable {
    public let queueDepth: Int

    public init(queueDepth: Int = ScreenCaptureStreamPlan.defaultQueueDepth) {
        self.queueDepth = queueDepth
    }

    public func prepare(
        configuration: CaptureConfiguration,
        sink: any ScreenCaptureSampleSink,
        onEvent: @escaping @Sendable (ScreenCaptureEvent) -> Void = { _ in }
    ) async throws -> ScreenCaptureSession {
        do {
            let plan = try ScreenCaptureStreamPlan(
                configuration: configuration,
                queueDepth: queueDepth
            )
            let content = try await SCShareableContent.excludingDesktopWindows(
                false,
                onScreenWindowsOnly: false
            )
            let inventory = Self.inventory(from: content)
            try inventory.resolve(configuration.source)
            let filter = try Self.filter(for: configuration.source, in: content)
            let router = ScreenCaptureOutputRouter(sink: sink) { failure in
                onEvent(.failed(failure))
            }
            let delegate = ScreenCaptureStreamDelegate(onEvent: onEvent)
            let stream = SCStream(
                filter: filter,
                configuration: plan.makeStreamConfiguration(),
                delegate: delegate
            )

            let queues = ScreenCaptureCallbackQueues()
            var outputTypes: [SCStreamOutputType] = [.screen]
            try stream.addStreamOutput(
                router,
                type: .screen,
                sampleHandlerQueue: queues.video
            )
            if plan.capturesSystemAudio {
                try stream.addStreamOutput(
                    router,
                    type: .audio,
                    sampleHandlerQueue: queues.systemAudio
                )
                outputTypes.append(.audio)
            }
            if plan.capturesMicrophone {
                try stream.addStreamOutput(
                    router,
                    type: .microphone,
                    sampleHandlerQueue: queues.microphone
                )
                outputTypes.append(.microphone)
            }

            let driver = ScreenCaptureKitStreamDriver(
                stream: stream,
                router: router,
                delegate: delegate,
                queues: queues,
                outputTypes: outputTypes
            )
            return ScreenCaptureSession(driver: driver)
        } catch let error as ScreenCaptureAdapterError {
            throw error
        } catch {
            throw ScreenCaptureAdapterError.captureFailed(
                ScreenCaptureFailureMapper.failure(for: error)
            )
        }
    }

    private static func inventory(from content: SCShareableContent) -> ScreenCaptureSourceInventory
    {
        ScreenCaptureSourceInventory(
            displays: content.displays.map {
                .init(id: $0.displayID, width: $0.width, height: $0.height)
            },
            applicationBundleIdentifiers: Set(
                content.applications.map(\.bundleIdentifier)
            ),
            windowIDs: Set(content.windows.map(\.windowID))
        )
    }

    private static func filter(
        for source: CaptureSource,
        in content: SCShareableContent
    ) throws -> SCContentFilter {
        switch source {
        case .display(let id), .region(let id, _):
            guard let display = content.displays.first(where: { $0.displayID == id }) else {
                throw ScreenCaptureAdapterError.sourceUnavailable(source)
            }
            let ownBundleIdentifier = Bundle.main.bundleIdentifier
            let excludedApplications = content.applications.filter {
                $0.bundleIdentifier == ownBundleIdentifier
            }
            return SCContentFilter(
                display: display,
                excludingApplications: excludedApplications,
                exceptingWindows: []
            )

        case .application(let bundleIdentifier, let displayID):
            guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
                throw ScreenCaptureAdapterError.sourceUnavailable(source)
            }
            let applications = content.applications.filter {
                $0.bundleIdentifier == bundleIdentifier
            }
            guard !applications.isEmpty else {
                throw ScreenCaptureAdapterError.sourceUnavailable(source)
            }
            return SCContentFilter(
                display: display,
                including: applications,
                exceptingWindows: []
            )

        case .window(let id):
            guard let window = content.windows.first(where: { $0.windowID == id }) else {
                throw ScreenCaptureAdapterError.sourceUnavailable(source)
            }
            return SCContentFilter(desktopIndependentWindow: window)
        }
    }
}

private final class ScreenCaptureKitStreamDriver: ScreenCaptureStreamDriving,
    @unchecked Sendable
{
    private let stream: SCStream
    private let router: ScreenCaptureOutputRouter
    private let delegate: ScreenCaptureStreamDelegate
    private let queues: ScreenCaptureCallbackQueues
    private let outputTypes: [SCStreamOutputType]

    init(
        stream: SCStream,
        router: ScreenCaptureOutputRouter,
        delegate: ScreenCaptureStreamDelegate,
        queues: ScreenCaptureCallbackQueues,
        outputTypes: [SCStreamOutputType]
    ) {
        self.stream = stream
        self.router = router
        self.delegate = delegate
        self.queues = queues
        self.outputTypes = outputTypes
    }

    func startCapture() async throws {
        try await stream.startCapture()
    }

    func stopCapture() async throws {
        try await stream.stopCapture()
        removeOutputs()
    }

    func cancelCapture() {
        removeOutputs()
    }

    private func removeOutputs() {
        for type in outputTypes {
            try? stream.removeStreamOutput(router, type: type)
        }
    }
}

private final class ScreenCaptureStreamDelegate: NSObject, SCStreamDelegate,
    @unchecked Sendable
{
    private let onEvent: @Sendable (ScreenCaptureEvent) -> Void

    init(onEvent: @escaping @Sendable (ScreenCaptureEvent) -> Void) {
        self.onEvent = onEvent
    }

    func stream(_ stream: SCStream, didStopWithError error: any Error) {
        onEvent(ScreenCaptureFailureMapper.event(for: error))
    }
}

private final class ScreenCaptureOutputRouter: NSObject, SCStreamOutput,
    @unchecked Sendable
{
    private let sink: any ScreenCaptureSampleSink
    private let onFailure: @Sendable (CaptureFailure) -> Void
    private let lock = NSLock()
    private var tracker = ScreenCaptureTimestampTracker()
    private var hasReportedFailure = false

    init(
        sink: any ScreenCaptureSampleSink,
        onFailure: @escaping @Sendable (CaptureFailure) -> Void
    ) {
        self.sink = sink
        self.onFailure = onFailure
    }

    func stream(
        _ stream: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of outputType: SCStreamOutputType
    ) {
        guard sampleBuffer.isValid,
            let kind = Self.kind(for: outputType),
            outputType != .screen || Self.isUsableScreenFrame(sampleBuffer)
        else {
            return
        }

        do {
            let timestamp = try observe(
                CMSampleBufferGetPresentationTimeStamp(sampleBuffer),
                kind: kind
            )
            sink.consume(
                ScreenCaptureSample(
                    kind: kind,
                    timestamp: timestamp,
                    buffer: sampleBuffer
                )
            )
        } catch {
            reportTimestampFailureOnce()
        }
    }

    private func observe(
        _ time: CMTime,
        kind: ScreenCaptureSampleKind
    ) throws -> ScreenCaptureTimestamp {
        lock.lock()
        defer { lock.unlock() }
        return try tracker.observe(time, kind: kind)
    }

    private func reportTimestampFailureOnce() {
        lock.lock()
        let shouldReport = !hasReportedFailure
        hasReportedFailure = true
        lock.unlock()
        if shouldReport {
            onFailure(
                CaptureFailure(
                    code: .internalFailure,
                    summary: "capture samples arrived with invalid timestamps"
                )
            )
        }
    }

    private static func kind(for outputType: SCStreamOutputType) -> ScreenCaptureSampleKind? {
        switch outputType {
        case .screen: .screen
        case .audio: .systemAudio
        case .microphone: .microphone
        @unknown default: nil
        }
    }

    private static func isUsableScreenFrame(_ sampleBuffer: CMSampleBuffer) -> Bool {
        guard
            let attachments = CMSampleBufferGetSampleAttachmentsArray(
                sampleBuffer,
                createIfNecessary: false
            ) as? [[SCStreamFrameInfo: Any]],
            let first = attachments.first,
            let rawStatus = first[.status] as? Int,
            let status = SCFrameStatus(rawValue: rawStatus)
        else {
            return false
        }
        return status == .complete || status == .started
    }
}

private final class ScreenCaptureCallbackQueues: @unchecked Sendable {
    let video = DispatchQueue(
        label: "com.aindaco.record.capture.video",
        qos: .userInteractive,
        autoreleaseFrequency: .workItem
    )
    let systemAudio = DispatchQueue(
        label: "com.aindaco.record.capture.system-audio",
        qos: .userInitiated,
        autoreleaseFrequency: .workItem
    )
    let microphone = DispatchQueue(
        label: "com.aindaco.record.capture.microphone",
        qos: .userInitiated,
        autoreleaseFrequency: .workItem
    )
}
