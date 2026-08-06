import Foundation

public struct RecordingPluginContext: Sendable {
    public let sessionID: UUID
    public let sessionDirectory: URL

    public init(sessionID: UUID, sessionDirectory: URL) {
        self.sessionID = sessionID
        self.sessionDirectory = sessionDirectory
    }
}

/// A recording-time plugin applies one reversible, local effect. Implementors
/// own their state snapshot and must make `deactivate` idempotent.
public protocol RecordingLifecyclePlugin: Sendable {
    var id: String { get }
    func activate(for context: RecordingPluginContext) async throws
    func deactivate(for context: RecordingPluginContext) async
}

/// Runs lifecycle plugins transactionally. Activation is ordered; restoration
/// is always reverse-ordered, including when a later plugin fails.
public actor PluginLifecycleCoordinator {
    public enum State: Equatable, Sendable {
        case idle
        case activating
        case active
        case deactivating
    }

    public enum LifecycleError: Error, Equatable {
        case invalidState(expected: State, actual: State)
        case activationFailed(pluginID: String, description: String)
    }

    public private(set) var state: State = .idle
    private var activePlugins: [any RecordingLifecyclePlugin] = []
    private var context: RecordingPluginContext?

    public init() {}

    public func activate(
        _ plugins: [any RecordingLifecyclePlugin],
        for context: RecordingPluginContext
    ) async throws {
        guard state == .idle else {
            throw LifecycleError.invalidState(expected: .idle, actual: state)
        }
        state = .activating
        self.context = context

        for plugin in plugins {
            do {
                try await plugin.activate(for: context)
                activePlugins.append(plugin)
            } catch {
                await restoreActivePlugins(for: context)
                self.context = nil
                state = .idle
                throw LifecycleError.activationFailed(
                    pluginID: plugin.id,
                    description: String(describing: error)
                )
            }
        }
        state = .active
    }

    public func deactivate() async {
        guard state == .active || state == .activating, let context else { return }
        state = .deactivating
        await restoreActivePlugins(for: context)
        self.context = nil
        state = .idle
    }

    private func restoreActivePlugins(for context: RecordingPluginContext) async {
        for plugin in activePlugins.reversed() {
            await plugin.deactivate(for: context)
        }
        activePlugins.removeAll(keepingCapacity: true)
    }
}
