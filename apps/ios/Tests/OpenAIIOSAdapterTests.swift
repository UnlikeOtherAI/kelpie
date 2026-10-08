import XCTest
@testable import Kelpie

/// iOS adaptation of the shared OpenAI-compatible core: execution-host
/// metadata, `ai-load` failure semantics and visible-tab pinning.
final class OpenAIIOSAdapterTests: XCTestCase {
    func testEndpointListReportsIOSExecutionHost() async {
        let router = Router()
        let context = await MainActor.run { HandlerContext() }
        AIHandler(context: context, router: router).register(on: router)

        let result = await router.handle(method: "ai-endpoints", body: [:]).json
        let host = result["executionHost"] as? [String: Any]
        XCTAssertEqual(result["success"] as? Bool, true)
        XCTAssertEqual(host?["platform"] as? String, "ios")
        XCTAssertTrue((host?["loopbackMeans"] as? String ?? "").contains("this iPhone or iPad"))
    }

    func testFailedOpenAILoadKeepsCurrentBackend() async {
        let router = Router()
        let context = await MainActor.run { HandlerContext() }
        AIHandler(context: context, router: router).register(on: router)
        let before = await MainActor.run { AIState.shared.backend }

        let result = await router.handle(
            method: "ai-load",
            body: ["backend": "openai", "endpoint": "no-such-endpoint-\(UUID().uuidString)"]
        ).json

        XCTAssertEqual(result["success"] as? Bool, false)
        XCTAssertEqual((result["error"] as? [String: Any])?["code"] as? String, "ENDPOINT_NOT_FOUND")
        let after = await MainActor.run { AIState.shared.backend }
        XCTAssertEqual(after, before)
    }

    @MainActor
    func testPinTabWithoutWebViewIsRejected() {
        let handler = AIHandler(context: HandlerContext(), router: Router())
        guard case .rejected(let response) = handler.pinTab(requested: nil) else {
            return XCTFail("Expected the pin to be rejected without a WebView")
        }
        XCTAssertEqual((response["error"] as? [String: Any])?["code"] as? String, "NO_WEBVIEW")
    }

    func testVisibleTabDispatcherForwardsWhilePinnedTabIsVisible() async {
        let base = RecordingDispatcher()
        let dispatcher = VisibleTabToolDispatcher(base: base, pinnedTabId: "tab-a", visibleTabId: { "tab-a" })

        let result = await dispatcher.dispatch(method: "get-page-text", body: ["tabId": "tab-a"])

        XCTAssertEqual(result["success"] as? Bool, true)
        XCTAssertEqual(base.calls.map(\.method), ["get-page-text"])
    }

    func testVisibleTabDispatcherRefusesAfterTabSwitch() async {
        let base = RecordingDispatcher()
        let dispatcher = VisibleTabToolDispatcher(base: base, pinnedTabId: "tab-a", visibleTabId: { "tab-b" })

        let result = await dispatcher.dispatch(method: "click", body: ["selector": "#buy"])

        XCTAssertEqual(result["success"] as? Bool, false)
        XCTAssertEqual((result["error"] as? [String: Any])?["code"] as? String, "TAB_CHANGED")
        XCTAssertTrue(base.calls.isEmpty, "No tool may run in a tab the run was not pinned to")
    }

    func testVisibleTabDispatcherWithoutPinForwards() async {
        let base = RecordingDispatcher()
        let dispatcher = VisibleTabToolDispatcher(base: base, pinnedTabId: nil, visibleTabId: { nil })

        _ = await dispatcher.dispatch(method: "get-current-url", body: [:])

        XCTAssertEqual(base.calls.count, 1)
    }
}
