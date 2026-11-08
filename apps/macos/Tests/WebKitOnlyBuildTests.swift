import XCTest
@testable import KelpieBrowser

#if KELPIE_WEBKIT_ONLY
@MainActor
final class WebKitOnlyBuildTests: XCTestCase {
    func testChromiumRequestIsRejectedWithoutSwitching() async {
        let state = RendererState()
        let router = Router()
        var switched = false
        RendererHandler(context: HandlerContext(), rendererState: state, onSwitch: { _ in switched = true })
            .register(on: router)

        let result = await router.handle(method: "set-renderer", body: ["engine": "chromium"]).json

        XCTAssertEqual(result["success"] as? Bool, false)
        XCTAssertEqual((result["error"] as? [String: Any])?["code"] as? String, "ENGINE_UNAVAILABLE")
        XCTAssertFalse(switched)
        XCTAssertEqual(state.activeEngine, .webkit)
        let available = await router.handle(method: "get-renderer", body: [:]).json
        XCTAssertEqual(available["available"] as? [String], ["webkit"])
    }
}
#endif
