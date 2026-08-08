import Foundation
import RecordCapture
import RecordCore
@preconcurrency import ScreenCaptureKit

enum SystemScreenCapturePickerMode: Sendable {
    case source
}

enum SystemScreenCapturePickerError: Error, Equatable {
    case alreadyPresenting
    case cancelled
    case failedToPresent
}

/// ScreenCaptureKit delivers picker observer callbacks on ReplayKit's XPC
/// queue. `SCContentFilter` is opaque selection state supplied by the system;
/// Record transfers it once to the main actor before inspecting or retaining
/// it for capture.
struct SendableContentFilter: @unchecked Sendable {
    let value: SCContentFilter
}

/// ScreenCaptureKit invokes its Objective-C observer on ReplayKit's XPC queue.
/// Keep that entry point on a deliberately non-actor-isolated proxy; placing
/// the conformance on the main-actor owner can make Swift's generated `@objc`
/// thunk assert before a `nonisolated` method body is reached.
final class SystemScreenCapturePickerObserverProxy: NSObject,
    SCContentSharingPickerObserver, @unchecked Sendable
{
    private let onCancel: @Sendable () -> Void
    private let onFailure: @Sendable () -> Void
    private let onSelection: @Sendable (SendableContentFilter) -> Void

    init(
        onCancel: @escaping @Sendable () -> Void,
        onFailure: @escaping @Sendable () -> Void,
        onSelection: @escaping @Sendable (SendableContentFilter) -> Void
    ) {
        self.onCancel = onCancel
        self.onFailure = onFailure
        self.onSelection = onSelection
    }

    func contentSharingPicker(
        _: SCContentSharingPicker,
        didCancelFor stream: SCStream?
    ) {
        guard stream == nil else { return }
        onCancel()
    }

    func contentSharingPicker(
        _: SCContentSharingPicker,
        didUpdateWith filter: SCContentFilter,
        for stream: SCStream?
    ) {
        guard stream == nil else { return }
        onSelection(.init(value: filter))
    }

    func contentSharingPickerStartDidFailWithError(_: any Error) {
        onFailure()
    }
}

/// One-shot bridge around Apple's shared picker. The observer is installed
/// only while a request is pending, and the opaque filter stays in memory for
/// the active recording rather than being serialized.
@MainActor
final class SystemScreenCapturePicker {
    private var continuation: CheckedContinuation<SystemScreenCaptureSelection, any Error>?
    private var observer: SystemScreenCapturePickerObserverProxy?

    func select(
        mode: SystemScreenCapturePickerMode,
        privacy: CapturePrivacyConfiguration
    ) async throws -> SystemScreenCaptureSelection {
        guard continuation == nil else {
            throw SystemScreenCapturePickerError.alreadyPresenting
        }

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                let picker = SCContentSharingPicker.shared
                var configuration = SCContentSharingPickerConfiguration()
                configuration.allowedPickerModes =
                    switch mode {
                    case .source: [.singleDisplay, .singleApplication, .singleWindow]
                    }
                configuration.allowsChangingSelectedContent = false
                configuration.excludedWindowIDs = []
                var excludedBundleIdentifiers = Set(
                    [Bundle.main.bundleIdentifier].compactMap { $0 }
                )
                if privacy.hideNotifications {
                    excludedBundleIdentifiers.formUnion(
                        ScreenCaptureFilterPlan.notificationCenterBundleIdentifiers
                    )
                }
                configuration.excludedBundleIDs = excludedBundleIdentifiers.sorted()
                picker.configuration = configuration
                picker.maximumStreamCount = 1
                let observer = SystemScreenCapturePickerObserverProxy(
                    onCancel: { [weak self] in
                        Task { @MainActor [weak self] in
                            self?.finish(.failure(SystemScreenCapturePickerError.cancelled))
                        }
                    },
                    onFailure: { [weak self] in
                        Task { @MainActor [weak self] in
                            self?.finish(.failure(SystemScreenCapturePickerError.failedToPresent))
                        }
                    },
                    onSelection: { [weak self] filter in
                        Task { @MainActor [weak self] in
                            guard let self else { return }
                            do {
                                finish(
                                    .success(
                                        try SystemScreenCaptureSelection(
                                            contentFilter: filter.value
                                        )
                                    )
                                )
                            } catch {
                                finish(.failure(error))
                            }
                        }
                    }
                )
                self.observer = observer
                picker.add(observer)
                picker.isActive = true
                picker.present()
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.finish(.failure(CancellationError()))
            }
        }
    }

    private func finish(
        _ result: Result<SystemScreenCaptureSelection, any Error>
    ) {
        guard let continuation else { return }
        self.continuation = nil
        let picker = SCContentSharingPicker.shared
        if let observer {
            picker.remove(observer)
        }
        observer = nil
        picker.isActive = false
        picker.configuration = nil
        continuation.resume(with: result)
    }
}
