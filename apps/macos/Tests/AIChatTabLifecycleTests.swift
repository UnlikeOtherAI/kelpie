import XCTest
import WebKit
@testable import Kelpie

@MainActor
final class AIChatTabLifecycleTests: XCTestCase {
    func testSnapshotTargetsRequestedTabEvenWhenAnotherTabIsActive() async throws {
        try await withTabStore { store, windowID in
            let first = try XCTUnwrap(store.activeTab)
            let second = store.addTab()
            try await loadFixture(on: first, title: "First page", brand: "Spotify")
            try await loadFixture(on: second, title: "Second page", brand: "Vodafone")
            let context = HandlerContext()
            context.renderer = second.renderer

            let firstPage = try await AIPageContext.gather(from: context, tabId: first.id.uuidString)
            let secondPage = try await AIPageContext.gather(from: context, tabId: second.id.uuidString)
            XCTAssertEqual(firstPage.title, "First page")
            XCTAssertEqual(firstPage.labels, ["Spotify"])
            XCTAssertEqual(secondPage.title, "Second page")
            XCTAssertEqual(secondPage.labels, ["Vodafone"])
            XCTAssertEqual(store.activeTabID, second.id)

            do {
                _ = try context.resolveRenderer(windowId: windowID, tabId: nil)
                XCTFail("Untargeted multi-tab read was accepted")
            } catch HandlerError.tabRequired { /* explicit targeting is required */ }

            _ = try await first.renderer.evaluateJS("JSON.stringify = function() { return '{}'; }; true")
            let response = await AIHandler(context: context).inferLocalChat(
                ["tabId": first.id.uuidString, "prompt": "Which companies?"],
                history: [],
                backend: AIBackendStore.Snapshot(
                    backend: "ollama", model: "fixture", capabilities: ["text"], ollamaEndpoint: "invalid-endpoint"
                )
            )
            XCTAssertEqual((response["error"] as? [String: Any])?["code"] as? String, "TAB_NOT_ACTIVE")
        }
    }

    func testSwitchingTabsDuringInferenceKeepsReplyInOriginatingConversation() async throws {
        try await withTabStore { store, _ in
            let first = try XCTUnwrap(store.activeTab)
            let second = store.addTab()
            store.selectTab(id: first.id)
            first.chatSession.input = "Remember amber otter"
            await first.chatSession.send { _, history in
                XCTAssertTrue(history.isEmpty)
                store.selectTab(id: second.id)
                await Task.yield()
                return AIChatReply(text: "amber otter")
            }
            XCTAssertTrue(second.chatSession.messages.isEmpty)
            store.selectTab(id: first.id)
            XCTAssertTrue(store.activeTab?.chatSession === first.chatSession)
            XCTAssertEqual(first.chatSession.messages.map(\.text), ["Remember amber otter", "amber otter"])
        }
    }

    func testClosingTabOrLastTabDiscardsLateRepliesAndErrors() async throws {
        for hasOtherTab in [false, true] {
            for fails in [false, true] {
                try await withTabStore { store, _ in
                    let tab = try XCTUnwrap(store.activeTab)
                    if hasOtherTab { store.addTab() }
                    tab.chatSession.input = "Question"
                    await tab.chatSession.send { _, _ in
                        store.closeTab(id: tab.id)
                        await Task.yield()
                        if fails { throw URLError(.timedOut) }
                        return AIChatReply(text: "Late answer")
                    }
                    XCTAssertFalse(store.tabs.contains { $0.id == tab.id })
                    XCTAssertEqual(store.tabs.count, 1)
                    assertClosed(tab.chatSession)
                    XCTAssertTrue(store.activeTab?.chatSession.messages.isEmpty == true)
                }
            }
        }
    }

    func testClosingWindowDiscardsLateRepliesAndErrorsForEveryTab() async throws {
        for fails in [false, true] {
            try await withTabStore { store, windowID in
                let first = try XCTUnwrap(store.activeTab)
                let second = store.addTab()
                second.chatSession.input = "Other conversation"
                await second.chatSession.send { _, _ in AIChatReply(text: "Other answer") }
                first.chatSession.input = "Question"
                await first.chatSession.send { _, _ in
                    WindowRegistry.shared.unregister(id: windowID)
                    await Task.yield()
                    if fails { throw URLError(.timedOut) }
                    return AIChatReply(text: "Late answer")
                }
                XCTAssertNil(WindowRegistry.shared.entry(for: windowID))
                assertClosed(first.chatSession)
                assertClosed(second.chatSession)
            }
        }
    }

    private func assertClosed(_ session: AIChatSession, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(session.messages.isEmpty, file: file, line: line)
        XCTAssertTrue(session.input.isEmpty, file: file, line: line)
        XCTAssertNil(session.errorMessage, file: file, line: line)
        XCTAssertFalse(session.isSending, file: file, line: line)
        XCTAssertFalse(session.allowActions, file: file, line: line)
    }

    private func withTabStore(_ body: (TabStore, String) async throws -> Void) async throws {
        // Do not restore real browsing sessions or leave test tabs in saved app state.
        let keys = ["sessionTabs", "sessionTabURLs", "sessionActiveIndex"]
        let saved = keys.map { UserDefaults.standard.object(forKey: $0) }
        SessionStore.clear()
        let store = TabStore()
        let windowID = UUID().uuidString
        WindowRegistry.shared.register(id: windowID, window: nil, tabStore: store)
        defer {
            WindowRegistry.shared.unregister(id: windowID)
            store.tabs.forEach { $0.renderer.invalidate() }
            for (key, value) in zip(keys, saved) {
                UserDefaults.standard.set(value, forKey: key)
            }
        }
        try await body(store, windowID)
    }

    private func loadFixture(on tab: Tab, title: String, brand: String) async throws {
        let view = try XCTUnwrap(tab.renderer.makeView() as? WKWebView)
        view.frame = CGRect(x: 0, y: 0, width: 800, height: 600)
        view.loadHTMLString(
            "<title>\(title)</title><body><p>Customer companies</p><img alt='\(brand)' width='40' height='40'></body>",
            baseURL: URL(string: "https://example.com/")
        )
        for _ in 0..<200 {
            if (try? await tab.renderer.evaluateJS("document.title")) as? String == title { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTFail("Fixture did not finish loading")
    }
}
