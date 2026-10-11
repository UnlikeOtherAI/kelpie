import XCTest
import WebKit
@testable import Kelpie

final class AIPageContextTests: XCTestCase {
    func testCompleteConversationSurvivesPromptComposition() throws {
        let messages = (0..<24).map { ["role": $0.isMultiple(of: 2) ? "user" : "assistant", "content": "turn-\($0)"] }
        let body: [String: Any] = ["messages": messages, "prompt": "Recall the first turn"]
        XCTAssertEqual(try AIConversation.messages(body).count, 24)
        let prompt = AIConversation.prompt(body)
        XCTAssertTrue(prompt.contains("turn-0"))
        XCTAssertTrue(prompt.contains("turn-23"))
        XCTAssertTrue(prompt.contains("Recall the first turn"))
    }

    func testMalformedHistoryFailsInsteadOfDroppingTurns() {
        XCTAssertThrowsError(try AIConversation.messages(["messages": [["role": "tool", "content": "hidden"]]]))
        XCTAssertThrowsError(try AIConversation.messages(["messages": [["role": "user", "content": 3]]]))
    }

    func testPageEvidenceKeepsLabelsBeyondBodyLimit() {
        let evidence = AIConversation.pageEvidence([
            "content": String(repeating: "x", count: 20000), "accessibleLabels": ["UnlikeOtherAI logo"],
            "title": "Test page", "url": "https://example.test"
        ])
        XCTAssertTrue(evidence.contains("UnlikeOtherAI logo"))
        XCTAssertTrue(evidence.contains("example.test"))
        XCTAssertLessThan(evidence.count, 13000)
    }

    func testCommonEvidenceOmitsValuesAndReportsRefusal() throws {
        let evidence = try AIConversation.commonEvidence(["ok": true, "value": [
            "title": "Page", "url": "https://example.test", "text": "Public", "truncated": true,
            "elements": [["name": "Logo", "value": "secret-input"]]
        ]])
        XCTAssertTrue(evidence.contains("Logo"))
        XCTAssertTrue(evidence.contains("truncated"))
        XCTAssertFalse(evidence.contains("secret-input"))
        XCTAssertThrowsError(try AIConversation.commonEvidence(["ok": false, "error": ["code": "TAB_NOT_FOUND", "message": "Closed"]]))
    }

    @MainActor
    func testSnapshotTargetsRequestedBackgroundTabAndAccessibleLogos() async throws {
        let context = HandlerContext()
        let store = TabStore(handlerContext: context)
        context.tabStore = store
        let first = try XCTUnwrap(store.activeBrowserTab)
        first.webView.loadHTMLString("""
        <html><head><title>Origin tab</title></head><body>Origin text
        <img alt="UnlikeOtherAI logo"><svg><title>Kelpie emblem</title></svg>
        <span aria-label="Accessible name"></span><img aria-hidden="true" alt="Hidden logo">
        </body></html>
        """, baseURL: URL(string: "https://origin.test"))
        try await waitForTitle("Origin tab", in: first.webView)
        let second = store.addBrowserTab()
        second.webView.loadHTMLString("<html><head><title>Other tab</title></head><body>Wrong page</body></html>", baseURL: nil)
        try await waitForTitle("Other tab", in: second.webView)
        context.webView = second.webView

        let snapshot = try await PageTextSnapshot.read(context: context, body: ["tabId": first.id.uuidString])
        XCTAssertEqual(snapshot["title"] as? String, "Origin tab")
        XCTAssertTrue((snapshot["content"] as? String ?? "").contains("Origin text"))
        let names = snapshot["accessibleLabels"] as? [String] ?? []
        XCTAssertTrue(names.contains("UnlikeOtherAI logo"))
        XCTAssertTrue(names.contains("Kelpie emblem"))
        XCTAssertTrue(names.contains("Accessible name"))
        XCTAssertFalse(names.contains("Hidden logo"))
        let router = Router()
        DOMHandler(context: context).register(on: router)
        LLMHandler(context: context).register(on: router)
        let dom = await router.handle(method: "get-dom", body: ["tabId": first.id.uuidString]).json
        XCTAssertEqual(dom["success"] as? Bool, true)
        XCTAssertTrue((dom["html"] as? String ?? "").contains("Origin text"))
        let tree = await router.handle(method: "get-accessibility-tree", body: ["tabId": first.id.uuidString]).json
        XCTAssertEqual(tree["success"] as? Bool, true)
        XCTAssertTrue(OpenAIAgentLoop.json(tree).contains("Origin text"))
        XCTAssertEqual(store.activeBrowserTabID, second.id)
        context.webView = first.webView // The UI's context pointer may lag a tab switch.
        let activeSnapshot = try await PageTextSnapshot.read(context: context, body: [:])
        XCTAssertEqual(activeSnapshot["title"] as? String, "Other tab")
        store.tabs.forEach { $0.invalidate() }
    }

    @MainActor
    func testUnknownTabAndReadFailureAreExplicit() async {
        let context = HandlerContext()
        do {
            _ = try await PageTextSnapshot.read(context: context, body: ["tabId": UUID().uuidString])
            XCTFail("Missing tabs must fail")
        } catch let error as AIHandlerError { XCTAssertEqual(error.code, "TAB_NOT_FOUND") } catch { XCTFail("Unexpected error") }

        let webView = WKWebView()
        context.webView = webView
        do {
            _ = try await PageTextSnapshot.read(context: context, body: ["selector": "["])
            XCTFail("A failed extraction must not be an empty success")
        } catch { }
    }

    @MainActor
    private func waitForTitle(_ title: String, in webView: WKWebView) async throws {
        for _ in 0..<200 {
            if webView.title == title { return }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTFail("Timed out loading fixture")
    }
}
