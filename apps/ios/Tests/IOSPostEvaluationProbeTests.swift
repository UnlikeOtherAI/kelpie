import WebKit
import XCTest
@testable import Kelpie

#if DEBUG
final class IOSPostEvaluationProbeTests: XCTestCase {
    @MainActor
    func testPreAuthorizationTimeoutAndExactViewTermination() async throws {
        let view = WKWebView()
        let other = WKWebView()
        let pending = IOSPostEvaluationProbe(view: view) {}
        let timeout = Task { @MainActor in try await pending.testAwaitReceipt(authorized: false) }
        while !pending.testIsWaiting { await Task.yield() }
        pending.expireIfUnapproved()
        do {
            try await timeout.value
            XCTFail("An unapproved probe must expire")
        } catch { XCTAssertEqual((error as? IOSWorkflowFailure)?.code, "TIMEOUT") }

        let authorized = IOSPostEvaluationProbe(view: view) {}
        let live = Task { @MainActor in try await authorized.testAwaitReceipt(authorized: true) }
        while !authorized.testIsWaiting { await Task.yield() }
        authorized.expireIfUnapproved()
        XCTAssertTrue(authorized.testIsWaiting, "An authorized live callback must remain fenced")
        IOSRendererDeadline.rendererTerminated(other)
        XCTAssertTrue(authorized.testIsWaiting, "Another view cannot retire the probe")
        IOSRendererDeadline.rendererTerminated(view)
        do {
            try await live.value
            XCTFail("A terminated renderer must fail its pending receipt")
        } catch {
            XCTAssertEqual((error as? IOSWorkflowFailure)?.code, "WEBVIEW_ERROR")
            XCTAssertEqual((error as? IOSWorkflowFailure)?.mayHaveCompleted, true)
        }
        XCTAssertFalse(authorized.testIsWaiting)
    }
}
#endif
