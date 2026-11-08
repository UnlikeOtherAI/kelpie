import XCTest
@testable import KelpieBrowser

@MainActor
final class StandaloneLaunchTests: XCTestCase {
    func testExplicitCliPortIsPreserved() {
        XCTAssertEqual(KelpieBrowserSession.standalonePort(arguments: ["Kelpie", "--port", "18434"]), 18434)
    }

    func testAbsentOrInvalidPortCannotTrapDuringLaunch() {
        for arguments in [["Kelpie"], ["Kelpie", "--port"], ["Kelpie", "--port", "-1"],
                          ["Kelpie", "--port", "65536"], ["Kelpie", "--port", "0"]] {
            XCTAssertEqual(KelpieBrowserSession.standalonePort(arguments: arguments), 8420)
        }
    }
}
