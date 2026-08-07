import ServiceManagement

enum LaunchAtLoginState: Equatable, Sendable {
    case disabled
    case enabled
    case requiresApproval
    case unavailable
}

@MainActor
protocol LaunchAtLoginServicing: AnyObject {
    var state: LaunchAtLoginState { get }
    func register() throws
    func unregister() throws
    func openSystemSettings()
}

@MainActor
final class SystemLaunchAtLoginService: LaunchAtLoginServicing {
    private let service: SMAppService

    init(service: SMAppService = .mainApp) {
        self.service = service
    }

    var state: LaunchAtLoginState {
        Self.state(for: service.status)
    }

    /// `SMAppService.mainApp` can report `.notFound` before the first
    /// registration even for a correctly installed application. Registration
    /// is the authoritative eligibility check, so keep the menu actionable and
    /// let `register()` surface a concrete macOS error if one exists.
    static func state(for status: SMAppService.Status) -> LaunchAtLoginState {
        switch status {
        case .notRegistered: .disabled
        case .enabled: .enabled
        case .requiresApproval: .requiresApproval
        case .notFound: .disabled
        @unknown default: .unavailable
        }
    }

    func register() throws {
        try service.register()
    }

    func unregister() throws {
        try service.unregister()
    }

    func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}

@MainActor
final class LaunchAtLoginController {
    private let service: any LaunchAtLoginServicing

    init(service: any LaunchAtLoginServicing = SystemLaunchAtLoginService()) {
        self.service = service
    }

    var state: LaunchAtLoginState { service.state }

    @discardableResult
    func toggle() throws -> LaunchAtLoginState {
        switch service.state {
        case .disabled:
            try service.register()
        case .enabled:
            try service.unregister()
        case .requiresApproval:
            service.openSystemSettings()
        case .unavailable:
            return .unavailable
        }
        return service.state
    }

    func openSystemSettings() {
        service.openSystemSettings()
    }
}
