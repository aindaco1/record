/// Tracks only the processes belonging to an application/window selection.
/// This transient state must never be persisted with recording metadata.
public struct CaptureSourceLifetime: Sendable {
    private var remainingProcessIDs: Set<Int32>
    private var isActive = true

    public init(processIDs: Set<Int32>) {
        remainingProcessIDs = processIDs
    }

    /// A display/region has no selected processes. For a multi-process source,
    /// losing one process does not end capture while another remains available.
    public mutating func applicationTerminated(processID: Int32) -> CaptureFailure? {
        guard isActive, remainingProcessIDs.remove(processID) != nil,
            remainingProcessIDs.isEmpty
        else { return nil }
        isActive = false
        return CaptureFailure(
            code: .sourceUnavailable,
            summary: "the selected capture source is no longer available"
        )
    }

    public mutating func cancel() {
        isActive = false
        remainingProcessIDs.removeAll()
    }
}
