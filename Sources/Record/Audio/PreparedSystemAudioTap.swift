import CoreAudio
import Foundation

/// Owns a Core Audio process tap between the permission check and capture
/// startup. Reusing the successful permission tap avoids creating and tearing
/// down an otherwise identical tap immediately before every audio recording.
final class PreparedSystemAudioTap: @unchecked Sendable {
    struct Handle: Sendable {
        let id: AudioObjectID
        let uuid: UUID
    }

    struct CreationError: Error, Equatable {
        let status: OSStatus
    }

    typealias Destroy = @Sendable (AudioObjectID) -> Void

    private let lock = NSLock()
    private var handle: Handle?
    private let destroy: Destroy

    static func create(name: String) throws -> PreparedSystemAudioTap {
        let description = CATapDescription(stereoGlobalTapButExcludeProcesses: [])
        description.name = name
        description.isPrivate = true
        description.muteBehavior = .unmuted

        var tapID = AudioObjectID(kAudioObjectUnknown)
        let status = AudioHardwareCreateProcessTap(description, &tapID)
        guard status == noErr, tapID != kAudioObjectUnknown else {
            if tapID != kAudioObjectUnknown {
                _ = AudioHardwareDestroyProcessTap(tapID)
            }
            throw CreationError(status: status)
        }
        return PreparedSystemAudioTap(
            handle: .init(id: tapID, uuid: description.uuid)
        )
    }

    init(
        handle: Handle,
        destroy: @escaping Destroy = { tapID in
            _ = AudioHardwareDestroyProcessTap(tapID)
        }
    ) {
        self.handle = handle
        self.destroy = destroy
    }

    /// Transfers destruction responsibility to the recorder exactly once.
    func consume() -> Handle? {
        lock.withLock {
            defer { handle = nil }
            return handle
        }
    }

    deinit {
        let unconsumed = lock.withLock {
            defer { handle = nil }
            return handle
        }
        if let unconsumed { destroy(unconsumed.id) }
    }
}
