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

/// One-shot bridge around Apple's shared picker. The observer is installed
/// only while a request is pending, and the opaque filter stays in memory for
/// the active recording rather than being serialized.
@MainActor
final class SystemScreenCapturePicker: NSObject,
    @preconcurrency SCContentSharingPickerObserver
{
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

    func contentSharingPicker(
        _ picker: SCContentSharingPicker,
        didCancelFor stream: SCStream?
    ) {
        guard stream == nil else { return }
        finish(.failure(SystemScreenCapturePickerError.cancelled))
    }

    func contentSharingPicker(
        _ picker: SCContentSharingPicker,
        didUpdateWith filter: SCContentFilter,
        for stream: SCStream?
    ) {
        guard stream == nil else { return }
        do {
            finish(.success(try SystemScreenCaptureSelection(contentFilter: filter)))
        } catch {
            finish(.failure(error))
        }
    }

    func contentSharingPickerStartDidFailWithError(_ error: any Error) {
        finish(.failure(SystemScreenCapturePickerError.failedToPresent))
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
