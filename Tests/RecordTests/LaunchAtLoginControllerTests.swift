@testable import Record
import ServiceManagement
import XCTest

@MainActor
final class LaunchAtLoginControllerTests: XCTestCase {
    func testMainAppNotFoundStatusRemainsActionable() {
        XCTAssertEqual(SystemLaunchAtLoginService.state(for: .notFound), .disabled)
    }

    func testMainAppStatusesMapWithoutGuessingAboutInstallLocation() {
        XCTAssertEqual(SystemLaunchAtLoginService.state(for: .notRegistered), .disabled)
        XCTAssertEqual(SystemLaunchAtLoginService.state(for: .enabled), .enabled)
        XCTAssertEqual(SystemLaunchAtLoginService.state(for: .requiresApproval), .requiresApproval)
    }

    func testDisabledServiceRegistersAndBecomesEnabled() throws {
        let service = FakeLaunchAtLoginService(state: .disabled)
        let controller = LaunchAtLoginController(service: service)

        XCTAssertEqual(try controller.toggle(), .enabled)
        XCTAssertEqual(service.registerCalls, 1)
        XCTAssertEqual(service.unregisterCalls, 0)
    }

    func testEnabledServiceUnregistersAndBecomesDisabled() throws {
        let service = FakeLaunchAtLoginService(state: .enabled)
        let controller = LaunchAtLoginController(service: service)

        XCTAssertEqual(try controller.toggle(), .disabled)
        XCTAssertEqual(service.registerCalls, 0)
        XCTAssertEqual(service.unregisterCalls, 1)
    }

    func testApprovalStateOpensSystemSettingsWithoutReregistering() throws {
        let service = FakeLaunchAtLoginService(state: .requiresApproval)
        let controller = LaunchAtLoginController(service: service)

        XCTAssertEqual(try controller.toggle(), .requiresApproval)
        XCTAssertEqual(service.openSettingsCalls, 1)
        XCTAssertEqual(service.registerCalls, 0)
        XCTAssertEqual(service.unregisterCalls, 0)
    }

    func testUnavailableServiceFailsClosed() throws {
        let service = FakeLaunchAtLoginService(state: .unavailable)
        let controller = LaunchAtLoginController(service: service)

        XCTAssertEqual(try controller.toggle(), .unavailable)
        XCTAssertEqual(service.registerCalls, 0)
        XCTAssertEqual(service.unregisterCalls, 0)
        XCTAssertEqual(service.openSettingsCalls, 0)
    }
}

@MainActor
private final class FakeLaunchAtLoginService: LaunchAtLoginServicing {
    var state: LaunchAtLoginState
    private(set) var registerCalls = 0
    private(set) var unregisterCalls = 0
    private(set) var openSettingsCalls = 0

    init(state: LaunchAtLoginState) {
        self.state = state
    }

    func register() throws {
        registerCalls += 1
        state = .enabled
    }

    func unregister() throws {
        unregisterCalls += 1
        state = .disabled
    }

    func openSystemSettings() {
        openSettingsCalls += 1
    }
}
