import FluidAudio
import Foundation
@testable import Record
import XCTest

final class FluidAudioOfflinePolicyTests: XCTestCase {
    func testEnforcementBlocksFluidAudioNetworkEntryPoint() async {
        FluidAudioOfflinePolicy.enforce()

        XCTAssertTrue(FluidAudioOfflinePolicy.isEnforced)
        do {
            _ = try await ModelHub.fetchWithAuth(
                from: URL(fileURLWithPath: "/network-must-remain-disabled")
            )
            XCTFail("offline mode must reject every FluidAudio network entry point")
        } catch DownloadError.networkDisabled {
            // Expected: the guard fails before URLSession can be reached.
        } catch {
            XCTFail("expected networkDisabled, received \(error)")
        }
    }
}
