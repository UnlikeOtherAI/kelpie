import XCTest
import WebKit
@testable import Kelpie

@MainActor
final class AIPageContextToolTests: XCTestCase {
    func testPageTextToolPreservesFieldsAndScopesAccessibleNames() async throws {
        let renderer = WKWebViewRenderer(dataStore: .nonPersistent())
        defer { renderer.invalidate() }
        let context = try await fixtureContext(renderer)
        let router = Router()
        LLMHandler(context: context).register(on: router)
        let response = await router.handle(method: "get-page-text", body: ["selector": "#customers"])
        let page = response.json
        XCTAssertEqual(response.statusCode, 200)
        XCTAssertEqual(page["title"] as? String, "Page tools fixture")
        XCTAssertEqual(page["content"] as? String, "Customer companies")
        XCTAssertEqual(page["wordCount"] as? Int, 2)
        XCTAssertEqual(page["language"] as? String, "en")
        XCTAssertTrue(page["byline"] is NSNull)
        XCTAssertEqual(page["excerpt"] as? String, "Customer companies")
        XCTAssertEqual(page["url"] as? String, "https://example.com/")
        XCTAssertEqual(page["accessibleLabels"] as? [String], ["Spotify", "Vodafone"])

        let logo = await router.handle(method: "get-page-text", body: ["selector": "#logo"])
        XCTAssertEqual(logo.json["accessibleLabels"] as? [String], ["Spotify"])
        let missing = await router.handle(method: "get-page-text", body: ["selector": "#absent"])
        XCTAssertEqual(missing.json["content"] as? String, "")
        XCTAssertEqual(missing.json["wordCount"] as? Int, 0)
        XCTAssertEqual(missing.json["accessibleLabels"] as? [String], [])
    }

    func testPageTextToolRetainsLongContentWhilePreloadBoundsTextSeparately() async throws {
        let renderer = WKWebViewRenderer(dataStore: .nonPersistent())
        defer { renderer.invalidate() }
        let context = try await fixtureContext(renderer)
        _ = try await renderer.evaluateJS("document.querySelector('#customers p').textContent = 'long page '.repeat(2000)")
        let router = Router()
        LLMHandler(context: context).register(on: router)
        let result = await router.handle(method: "get-page-text", body: ["selector": "#customers"])
        XCTAssertGreaterThan((result.json["content"] as? String)?.count ?? 0, 16000)
        XCTAssertEqual(result.json["textTruncated"] as? Bool, false)
        router.handlerContext = context
        let preload = try await AIHandler(context: context, router: router).preloadedContext(mode: "page_text", tabId: nil)
        let serialized = try XCTUnwrap(preload)
        XCTAssertTrue(serialized.hasPrefix("{\"accessibleLabels\":"), "Keep names before body text when model input is truncated")
        let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(serialized.utf8)) as? [String: Any])
        XCTAssertLessThanOrEqual((payload["content"] as? String)?.count ?? 0, 12000)
        XCTAssertEqual(payload["textTruncated"] as? Bool, true)
        XCTAssertTrue((payload["accessibleLabels"] as? [String] ?? []).contains("Spotify"))
    }

    func testPageTextToolRejectsMalformedSnapshot() async throws {
        let renderer = WKWebViewRenderer(dataStore: .nonPersistent())
        defer { renderer.invalidate() }
        let context = try await fixtureContext(renderer)
        _ = try await renderer.evaluateJS("JSON.stringify = function() { return '{}'; }; true")
        let router = Router()
        LLMHandler(context: context).register(on: router)
        let result = await router.handle(method: "get-page-text", body: [:])
        XCTAssertEqual((result.json["error"] as? [String: Any])?["code"] as? String, "EVAL_ERROR")
    }

    func testOpenAIPreloadIncludesLabelsAndFailsBeforeModelRequest() async throws {
        let renderer = WKWebViewRenderer(dataStore: .nonPersistent())
        defer { renderer.invalidate() }
        let context = try await fixtureContext(renderer)
        let transport = FakeOpenAITransport { request in
            if request.url?.path.hasSuffix("/models") == true {
                return .init(body: OpenAIFixtures.json(OpenAIFixtures.strataModels))
            }
            return .init(headers: ["Content-Type": "text/event-stream"], body: OpenAIFixtures.answerStream("Customers"))
        }
        let service = OpenAIFixtures.service(transport: transport)
        let endpoint = try await service.save(.init(
            name: "Fixture",
            baseURL: "http://127.0.0.1:18880/v1",
            model: "qwen3.8-flash-next-ud-q4_k_xl",
            declared: OpenAIDeclaredCapabilities()
        ))
        _ = try await service.select(endpoint.id, model: nil)
        let router = Router()
        router.handlerContext = context
        let handler = AIHandler(context: context, router: router, openAIService: service)
        let body: [String: Any] = ["prompt": "Which customers?", "context": "page_text"]
        let success = await handler.inferWithOpenAI(body)
        XCTAssertEqual(success["success"] as? Bool, true)
        let request = try XCTUnwrap(transport.requests.last)
        let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: try XCTUnwrap(request.httpBody)) as? [String: Any])
        let messages = try XCTUnwrap(payload["messages"] as? [[String: Any]])
        XCTAssertTrue((messages.last?["content"] as? String ?? "").contains("Spotify"))
        let beforeFailure = transport.requests.count
        context.renderer = nil // The captured renderer is gone; refuse before calling the provider.
        for mode in ["page_text", "dom", "accessibility"] {
            let failure = await handler.inferWithOpenAI(["prompt": "Which customers?", "context": mode])
            XCTAssertEqual((failure["error"] as? [String: Any])?["code"] as? String, "PAGE_CONTEXT_UNAVAILABLE")
            XCTAssertEqual(transport.requests.count, beforeFailure, "Failed preload contacted the model")
        }
        context.renderer = renderer
        let explicit = await handler.inferWithOpenAI(["prompt": "Summarize", "context": "page_text", "text": "Supplied evidence"])
        XCTAssertEqual(explicit["success"] as? Bool, true, "Explicit text must not attempt page extraction")
    }

    private func fixtureContext(_ renderer: WKWebViewRenderer) async throws -> HandlerContext {
        let view = try XCTUnwrap(renderer.makeView() as? WKWebView)
        view.frame = CGRect(x: 0, y: 0, width: 800, height: 600)
        view.loadHTMLString("""
        <html lang="en"><title>Page tools fixture</title><body>
        <section id="customers"><p>Customer companies</p><img id="logo" alt="Spotify" width="40" height="40">
        <svg aria-label="Vodafone" width="40" height="40"></svg></section>
        <img alt="Outside brand" width="40" height="40"></body></html>
        """, baseURL: URL(string: "https://example.com/"))
        for _ in 0..<200 {
            if (try? await renderer.evaluateJS("document.title")) as? String == "Page tools fixture" {
                let context = HandlerContext()
                context.renderer = renderer
                context.activeEngineIsChromium = true
                return context
            }
            try await Task.sleep(for: .milliseconds(20))
        }
        throw URLError(.timedOut)
    }
}
