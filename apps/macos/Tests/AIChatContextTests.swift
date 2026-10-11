import XCTest
import WebKit
@testable import Kelpie

@MainActor
final class AIChatContextTests: XCTestCase {
    func testEveryBackendReceivesAllHistoryAndPinnedTab() {
        let history = (0..<24).map { AIChatMessage(role: $0.isMultiple(of: 2) ? .user : .assistant, text: "Turn \($0)") }
        for backend in [AIBackend.ollama, .native, .openai] {
            let body = AIState.chatRequest(prompt: "Follow up", history: history, tabId: "tab-A", backend: backend, allowActions: false)
            XCTAssertEqual(body["tabId"] as? String, "tab-A")
            XCTAssertEqual(body["messages"] as? [[String: String]], history.map { $0.apiPayload })
            XCTAssertEqual(body["prompt"] as? String, "Follow up")
        }
    }

    func testConversationSurvivesNavigationAndIsIsolatedBetweenTabs() async {
        let first = Tab()
        let second = Tab()
        first.chatSession.input = "Remember amber otter"
        await first.chatSession.send { _, _ in AIChatReply(text: "I will remember it.") }
        first.chatSession.input = "A draft"
        first.chatSession.allowActions = true
        first.currentURL = "https://example.com/next"
        XCTAssertEqual(first.chatSession.messages.count, 2)
        XCTAssertEqual(first.chatSession.input, "A draft")
        XCTAssertFalse(first.chatSession.allowActions)
        XCTAssertTrue(second.chatSession.messages.isEmpty)
        XCTAssertNotEqual(first.chatSession.tabId, second.chatSession.tabId)
        await first.chatSession.send { prompt, history in
            XCTAssertEqual(prompt, "A draft")
            XCTAssertEqual(history.first?.text, "Remember amber otter")
            return AIChatReply(text: "amber otter")
        }
        XCTAssertEqual(first.chatSession.messages.last?.text, "amber otter")
    }

    func testClosingDiscardsLateRepliesAndErrorsAndPreventsFurtherSends() async {
        for fails in [false, true] {
            let session = AIChatSession(tabId: "tab-A")
            session.input = "Question"
            await session.send { _, _ in
                session.close()
                if fails { throw URLError(.timedOut) }
                return AIChatReply(text: "Late reply")
            }
            XCTAssertTrue(session.messages.isEmpty)
            XCTAssertNil(session.errorMessage)
            XCTAssertFalse(session.isSending)
            session.input = "Another question"
            await session.send { _, _ in
                XCTFail("Closed tab sent a request")
                return AIChatReply(text: "unexpected")
            }
        }
    }

    func testDuplicateSendCannotOverlapAnInFlightTurn() async {
        let session = AIChatSession(tabId: "tab-A")
        session.input = "First"
        await session.send { _, _ in
            session.input = "Second"
            await session.send { _, _ in
                XCTFail("Overlapping inference")
                return AIChatReply(text: "unexpected")
            }
            return AIChatReply(text: "First answer")
        }
        XCTAssertEqual(session.messages.map(\.text), ["First", "First answer"])
        XCTAssertEqual(session.input, "Second")
    }

    func testPageSnapshotIncludesAccessibleLogosAndReportsTruncation() async throws {
        let renderer = WKWebViewRenderer(dataStore: .nonPersistent())
        defer { renderer.invalidate() }
        let view = try XCTUnwrap(renderer.makeView() as? WKWebView)
        view.frame = CGRect(x: 0, y: 0, width: 800, height: 600)
        view.loadHTMLString("""
        <title>Context fixture</title><body><p>Customer companies</p>
        <img alt="Spotify" width="40" height="40"><svg width="40" height="40"><title>Vodafone</title></svg>
        <div role="img" aria-label="Philips" style="width:40px;height:40px"></div>
        <span id="airline">American Airlines</span><svg aria-labelledby="airline" width="40" height="40"></svg>
        <div aria-label="Hidden brand" style="display:none"></div>
        <p>\(String(repeating: "long page ", count: 2000))</p></body>
        """, baseURL: URL(string: "https://example.com/"))
        for _ in 0..<200 {
            if (try? await renderer.evaluateJS("document.title")) as? String == "Context fixture" { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        let context = HandlerContext()
        context.renderer = renderer
        context.activeEngineIsChromium = true // Route directly to this isolated test renderer.
        let page = try await AIPageContext.gather(from: context, tabId: nil)
        XCTAssertEqual(page.title, "Context fixture")
        XCTAssertTrue(page.text.contains("Customer companies"))
        for label in ["Spotify", "Vodafone", "Philips", "American Airlines"] {
            XCTAssertTrue(page.labels.contains(label), label)
        }
        XCTAssertFalse(page.labels.contains("Hidden brand"))
        XCTAssertTrue(page.textTruncated)
        let prompt = try page.nativePrompt(prompt: "What did I say?", history: [["role": "user", "content": "amber otter"]])
        XCTAssertTrue(prompt.contains("amber otter"))
        XCTAssertTrue(prompt.contains("conversation history"))
        _ = try await renderer.evaluateJS("JSON.stringify = function() { return '{}'; }; true")
        do {
            _ = try await AIPageContext.gather(from: context, tabId: nil)
            XCTFail("Malformed snapshot was accepted as empty content")
        } catch is DecodingError { /* expected */ }
    }

    func testClosedTabIsRejectedInsteadOfReturningEmptyPage() async {
        do {
            _ = try await AIPageContext.gather(from: HandlerContext(), tabId: UUID().uuidString)
            XCTFail("Missing tab was accepted")
        } catch { XCTAssertTrue(error is HandlerError) }
    }

    func testSuppliedTextAndFullHistoryArePreservedInNativePrompt() async throws {
        let handler = AIHandler(context: HandlerContext())
        let supplied = "Explicit context with a logo named Philips"
        let history = (0..<24).map { index in
            ["role": index.isMultiple(of: 2) ? "user" : "assistant", "content": "Turn \(index)"]
        }
        // Explicit context remains usable without a browser tab or a page extraction.
        let page = try await handler.localChatPage(
            ["text": supplied, "context": "page_text", "messages": history], tabId: UUID().uuidString
        )
        XCTAssertEqual(page.text, supplied)
        let prompt = try page.nativePrompt(prompt: "Recall the first turn", history: history)
        let prefix = "Conversation (JSON, oldest first):\n"
        let serialized = try XCTUnwrap(prompt.components(separatedBy: prefix).last?
            .components(separatedBy: "\n\nAnswer the last user message:").first)
        let messages = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(serialized.utf8)) as? [[String: String]])
        XCTAssertEqual(Array(messages.dropLast()), history)
        XCTAssertEqual(messages.last, ["role": "user", "content": "Recall the first turn"])
        XCTAssertTrue(prompt.contains(supplied))
    }
}
