import Foundation
import RecordCapture
import RecordCore
@preconcurrency import ScreenCaptureKit

enum SystemScreenCapturePickerMode: Sendable {
    case source
    case displayForRegion
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
private struct SendableContentFilter: @unchecked Sendable {
    let value: SCContentFilter
}

/// One-shot bridge around Apple's shared picker. The observer is installed
/// only while a request is pending, and the opaque filter stays in memory for
/// the active recording rather than being serialized.
@MainActor
final class SystemScreenCapturePicker: NSObject, SCContentSharingPickerObserver {
    private var continuation: CheckedContinuation<SystemScreenCaptureSelection, any Error>?

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
                    case .displayForRegion: [.singleDisplay]
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
                picker.add(self)
                picker.isActive = true
                picker.present()
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.finish(.failure(CancellationError()))
            }
        }
    }

    nonisolated func contentSharingPicker(
        _: SCContentSharingPicker,
        didCancelFor stream: SCStream?
    ) {
        guard stream == nil else { return }
        Task { @MainActor [weak self] in
            self?.finish(.failure(SystemScreenCapturePickerError.cancelled))
        }
    }

    nonisolated func contentSharingPicker(
        _: SCContentSharingPicker,
        didUpdateWith filter: SCContentFilter,
        for stream: SCStream?
    ) {
        guard stream == nil else { return }
        let filter = SendableContentFilter(value: filter)
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                finish(
                    .success(
                        try SystemScreenCaptureSelection(contentFilter: filter.value)
                    )
                )
            } catch {
                finish(.failure(error))
            }
        }
    }

    nonisolated func contentSharingPickerStartDidFailWithError(_: any Error) {
        Task { @MainActor [weak self] in
            self?.finish(.failure(SystemScreenCapturePickerError.failedToPresent))
        }
    }

    private func finish(
        _ result: Result<SystemScreenCaptureSelection, any Error>
    ) {
        guard let continuation else { return }
        self.continuation = nil
        let picker = SCContentSharingPicker.shared
        picker.remove(self)
        picker.isActive = false
        picker.configuration = nil
        continuation.resume(with: result)
    }
}
