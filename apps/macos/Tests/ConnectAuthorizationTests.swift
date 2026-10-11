import XCTest
import WebKit
@testable import Kelpie

final class ConnectAuthorizationTests: XCTestCase {
    @MainActor
    func testRemoteRouterSharesCanonicalAdmissionUntilRendererRetires() async {
        let owner = Router()
        let remote = Router()
        remote.browserReferenceOwner = owner
        var calls = 0
        remote.register("get-visible-elements") { _ in calls += 1; return ["success": true] }
        XCTAssertTrue(owner.browserLease.begin())
        let busy = await remote.handle(method: "get-visible-elements", body: [:]).json
        XCTAssertEqual((busy["error"] as? [String: Any])?["code"] as? String, "BUSY")
        XCTAssertEqual(calls, 0)
        owner.browserLease.retainPending()
        owner.browserLease.end()
        let pending = await remote.handle(method: "get-visible-elements", body: [:]).json
        XCTAssertEqual((pending["error"] as? [String: Any])?["code"] as? String, "BUSY")
        owner.browserLease.retirePending()
        let ready = await remote.handle(method: "get-visible-elements", body: [:]).json
        XCTAssertEqual(ready["success"] as? Bool, true)
        XCTAssertEqual(calls, 1)
    }

    @MainActor
    func testSnapshotSelectorsIdentifyDuplicateButtonsAndEmptyInputs() async throws {
        let context = HandlerContext()
        #if os(iOS)
        let view = WKWebView(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
        context.webView = view
        #else
        let renderer = WKWebViewRenderer(dataStore: .nonPersistent())
        defer { renderer.invalidate() }
        let view = try XCTUnwrap(renderer.makeView() as? WKWebView)
        context.renderer = renderer
        context.activeEngineIsChromium = true // Isolated renderer; do not resolve the host app's windows.
        #endif
        view.loadHTMLString("<title>Controls</title><button class='same'>Go</button><button class='same'>Go</button><input>", baseURL: nil)
        for _ in 0..<200 {
            if !view.isLoading, view.title == "Controls" { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        let router = Router()
        LLMHandler(context: context).register(on: router)
        let snapshot = await router.handle(method: "get-visible-elements", body: ["interactableOnly": true]).json
        XCTAssertEqual(snapshot["success"] as? Bool, true)
        let elements = try XCTUnwrap(snapshot["elements"] as? [[String: Any]])
        let selectors = elements.compactMap { $0["selector"] as? String }
        XCTAssertEqual(selectors.count, 3)
        XCTAssertEqual(Set(selectors).count, 3)
        for selector in selectors {
            XCTAssertLessThanOrEqual(selector.utf16.count, 2000)
            let matches = try await view.evaluateJavaScript("document.querySelectorAll('\(JSEscape.string(selector))').length")
            XCTAssertEqual(matches as? Int, 1)
        }
    }
    func testExtractionCancellationCannotCancelAnotherRequest() async throws {
        let extraction = InferenceRequest()
        let personChat = InferenceRequest()
        extraction.cancel()
        #if os(iOS)
        let stopped = await LocalInference.shared.execute("infer", body: ["prompt": "Hello"], request: extraction)
        XCTAssertEqual((stopped["error"] as? [String: Any])?["code"] as? String, "INFERENCE_CANCELLED")
        let status = await LocalInference.shared.execute("status", request: personChat)
        XCTAssertEqual(status["success"] as? Bool, true)
        #else
        XCTAssertTrue(extraction.isCancelled)
        XCTAssertFalse(personChat.isCancelled)
        #endif
    }
    #if os(iOS)
    @MainActor
    func testPageContextReadKeepsItsBeforeAndAfterJobFence() async throws {
        let context = HandlerContext()
        let view = WKWebView()
        context.webView = view
        context.remoteDocumentGuard = { false }
        do {
            _ = try await PageTextSnapshot.object(context: context, body: [:], script: "({value:1})")
            XCTFail("Revoked job must not read page context")
        } catch is CancellationError { }
        var checks = 0
        context.remoteDocumentGuard = { checks += 1; return checks == 1 }
        do {
            _ = try await PageTextSnapshot.object(context: context, body: [:], script: "({value:1})")
            XCTFail("Revocation during evaluation must discard page context")
        } catch is CancellationError { }
        XCTAssertEqual(checks, 2)
    }
    #endif
    @MainActor
    func testNavigationCompletionBelongsToItsIssuedNativeObject() {
        let token = NSObject()
        let lease = ConnectNavigationLease(initial: "old")
        lease.issued(token)
        XCTAssertFalse(lease.allowsRead(version: "old", loading: false, authorized: true))
        lease.started(previous: "old", version: "new", navigation: token)
        XCTAssertTrue(lease.allowsRead(version: "new", loading: false, authorized: true))
        XCTAssertFalse(lease.allowsRead(version: "new", loading: true, authorized: true))
        XCTAssertFalse(lease.allowsRead(version: "new", loading: false, authorized: false))
        lease.started(previous: "new", version: "later", navigation: NSObject())
        XCTAssertFalse(lease.allowsRead(version: "later", loading: false, authorized: true))
    }

    @MainActor
    func testUnrelatedNavigationCannotSupplyCompletionMetadata() {
        let lease = ConnectNavigationLease(initial: "old")
        lease.issued(NSObject())
        lease.started(previous: "old", version: "unrelated", navigation: NSObject())
        XCTAssertFalse(lease.allowsRead(version: "unrelated", loading: false, authorized: true))
        XCTAssertFalse(lease.allowsWait(version: "unrelated", authorized: true))
    }

    func testWireTextBoundsPreserveUnicode() {
        XCTAssertEqual(ConnectText.bounded(String(repeating: "😀", count: 100), to: 120).utf16.count, 120)
        XCTAssertEqual(ConnectText.bounded("a😀", to: 2), "a")
        XCTAssertEqual(ConnectText.bounded("e\u{301}", to: 1), "")
    }

    func testCancelledAndReplacementJobsCannotBorrowAuthority() throws {
        let command: [String: Any] = ["jobId": "job", "attemptId": "first", "deadline": "2030-01-01T00:00:00.123Z"]
        let authorization = try XCTUnwrap(ConnectAuthorization(command))
        let now = try XCTUnwrap(ConnectAuthorization.parseDeadline("2029-01-01T00:00:00Z"))
        XCTAssertTrue(authorization.matches(command, now: now))
        XCTAssertFalse(authorization.matches(nil, now: now))
        XCTAssertFalse(authorization.matches(["jobId": "job", "attemptId": "replacement"], now: now))
        XCTAssertFalse(authorization.matches(["jobId": "other", "attemptId": "first"], now: now))
        XCTAssertFalse(authorization.matches(command, now: authorization.deadline))
        XCTAssertNil(ConnectAuthorization(["jobId": "job", "attemptId": "first", "deadline": "invalid"]))
    }

    @MainActor
    func testNavigationChangesOnlyThatDocumentsPin() {
        let first = NSObject()
        let second = NSObject()
        let firstPin = ConnectDocument.version(first)
        let secondPin = ConnectDocument.version(second)
        XCTAssertEqual(ConnectDocument.version(first), firstPin)
        ConnectDocument.navigated(first)
        XCTAssertNotEqual(ConnectDocument.version(first), firstPin)
        XCTAssertEqual(ConnectDocument.version(second), secondPin)
    }
}
