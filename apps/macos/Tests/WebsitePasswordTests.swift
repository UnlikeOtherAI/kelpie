import AuthenticationServices
import WebKit
import XCTest
@testable import KelpieBrowser

final class WebsitePasswordTests: XCTestCase {
    func testLoginIdentityUsesHTTPSOriginAndExactUsername() throws {
        let url = try XCTUnwrap(URL(string: "https://Example.com:443/account?to=home"))
        let login = try XCTUnwrap(WebsitePasswordStore.Login(url: url, username: "ALICE"))
        XCTAssertEqual(login.origin, "https://example.com")
        XCTAssertEqual(login.username, "ALICE")
        for address in ["http://example.com", "file:///login", "https://name@example.com"] {
            XCTAssertNil(WebsitePasswordStore.Login(url: try XCTUnwrap(URL(string: address)), username: "alice"))
        }
        XCTAssertNil(WebsitePasswordStore.Login(url: url, username: ""))
    }

    @MainActor
    func testAutoFillMatchesTheRequestedSiteAndAccount() throws {
        let url = try XCTUnwrap(URL(string: "https://example.invalid/login"))
        let login = try XCTUnwrap(WebsitePasswordStore.Login(url: url, username: "saved"))
        let identity = WebsitePasswordSuggestions.identity(login)
        XCTAssertEqual(identity.user, login.username)
        XCTAssertEqual(identity.recordIdentifier, login.account)
        XCTAssertTrue(WebsitePasswordSuggestions.matches(login, service: identity.serviceIdentifier))
        XCTAssertTrue(WebsitePasswordSuggestions.matches(login, service: .init(identifier: "EXAMPLE.INVALID", type: .domain)))
        for address in ["http://example.invalid", "https://m.example.invalid", "https://example.invalid:8443"] {
            XCTAssertFalse(WebsitePasswordSuggestions.matches(login, service: .init(identifier: address, type: .URL)))
        }
        let portURL = try XCTUnwrap(URL(string: "https://example.invalid:8443"))
        let portLogin = try XCTUnwrap(WebsitePasswordStore.Login(url: portURL, username: "saved"))
        XCTAssertFalse(WebsitePasswordSuggestions.matches(portLogin, service: .init(identifier: "example.invalid", type: .domain)))
    }

    @MainActor
    func testWebKitFillsOnlyTheInspectedDocument() async throws {
        let view = WKWebView(frame: NSRect(x: 0, y: 0, width: 640, height: 480))
        let url = try XCTUnwrap(URL(string: "https://example.invalid/signin"))
        let html = "<form method='post'><input autocomplete='username'><input type='password'></form>"
        view.loadHTMLString(html, baseURL: url)
        for _ in 0..<150 {
            if (try? await view.evaluateJavaScript("document.querySelector('form') !== null")) as? Bool == true { break }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        _ = try await view.evaluateJavaScript("document.querySelector('input').focus()")
        let inspected = try await WebsitePasswordForm.inspect(in: view, frame: nil, url: url, submitting: false)
        let form = try XCTUnwrap(inspected)
        let login = try XCTUnwrap(WebsitePasswordStore.Login(url: url, username: "tester"))
        let disposable = UUID().uuidString
        try await form.fill(login: login, password: disposable)
        let filled = try await view.evaluateJavaScript("document.querySelector('[type=password]').value.length")
        XCTAssertEqual(filled as? Int, disposable.count)
        let replacement = "<input type='password'>"
        _ = try await view.callAsyncJavaScript(
            "document.body.innerHTML = html", arguments: ["html": replacement], in: nil, contentWorld: .page
        )
        try await form.fill(login: login, password: disposable)
        let untouched = try await view.evaluateJavaScript("document.querySelector('input').value.length")
        XCTAssertEqual(untouched as? Int, 0)
    }

    @MainActor
    func testPasswordDocumentFetchOmitsPayloadAndQueryFromInspector() async throws {
        let config = WKWebViewConfiguration()
        let inbox = NetworkInbox()
        let received = expectation(description: "Received redacted network metadata")
        inbox.received = { received.fulfill() }
        let scripts = config.userContentController
        scripts.add(inbox, name: "kelpieNetwork")
        let fakeFetch = "window.fetch = async () => new Response('sensitive response', {status: 200});"
        scripts.addUserScript(WKUserScript(source: fakeFetch, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        scripts.addUserScript(NetworkBridge.bridgeScript)
        let view = WKWebView(frame: .zero, configuration: config)
        let html = """
        <input type="password">
        <script>fetch('/login?private=query', {method:'POST',body:'sensitive request'})</script>
        """
        view.loadHTMLString(html, baseURL: URL(string: "https://example.invalid/"))
        await fulfillment(of: [received], timeout: 5)
        XCTAssertEqual(inbox.message["url"] as? String, "https://example.invalid")
        XCTAssertEqual(inbox.message["statusCode"] as? Int, 200)
        for key in ["requestBody", "responseBody", "requestHeaders", "responseHeaders"] {
            XCTAssertNil(inbox.message[key])
        }
    }

    private final class NetworkInbox: NSObject, WKScriptMessageHandler {
        var message: [String: Any] = [:]
        var received: (() -> Void)?
        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            self.message = message.body as? [String: Any] ?? [:]
            received?()
        }
    }

    func testSaveUpdateAndDeletionStayWithinWebsitePasswordService() throws {
        let prefix = "rocks.kelpie.password-test." + UUID().uuidString
        let store = WebsitePasswordStore(service: prefix)
        let other = WebsitePasswordStore(service: prefix + ".other")
        defer {
            try? store.delete(nil)
            try? other.delete(nil)
        }
        let url = try XCTUnwrap(URL(string: "https://example.invalid:8443/login"))
        let first = try XCTUnwrap(WebsitePasswordStore.Login(url: url, username: "first"))
        let second = try XCTUnwrap(WebsitePasswordStore.Login(url: url, username: "second"))
        let secret = UUID().uuidString
        try store.save(UUID().uuidString, for: first)
        try store.save(secret, for: first)
        try store.save(UUID().uuidString, for: second)
        try other.save(secret, for: first)
        XCTAssertEqual(try store.logins(), [first, second])
        XCTAssertTrue(try store.password(for: first) == secret)
        try store.delete(first)
        XCTAssertEqual(try store.logins(), [second])
        try store.save(secret, for: first)
        try store.delete(nil)
        XCTAssertTrue(try store.logins().isEmpty)
        XCTAssertTrue(try other.password(for: first) == secret)
    }
}
