import WebKit
import XCTest
@testable import Kelpie

final class ScriptWorkflowAdmissionTests: XCTestCase {
    typealias Body = [String: Any]
    private let tap: Body = ["action": "tap", "target": ["role": "button", "name": "Submit"]]

    private func workflow(_ steps: [Body], _ extra: Body = [:]) -> Body {
        ["version": 1, "tabId": "test-tab", "actions": steps].merging(extra) { _, new in new }
    }

    private func assertRejected(_ body: Body, _ code: String, line: UInt = #line) {
        XCTAssertThrowsError(try ScriptBoundWorkflow(body), line: line) {
            XCTAssertEqual(($0 as? ScriptWorkflowFailure)?.code, code, line: line)
        }
    }

    func testFullPreflightRejectsForeignSessionsAndUnsupportedKeyAfterTap() throws {
        XCTAssertEqual(try ScriptBoundWorkflow(workflow([tap])).steps.count, 1)
        for session in ["unknown-session", "other-owner-session"] {
            assertRejected(workflow([tap], ["sessionId": session]), "SESSION_UNSUPPORTED")
        }
        assertRejected(workflow([tap, ["action": "press-key", "key": "Enter"]]), "UNSUPPORTED_SCRIPT_ACTION")
        assertRejected(workflow([tap], ["continueOnError": true]), "INVALID_SCRIPT")
        assertRejected(workflow([tap], ["inputs": ["unused": ["type": "string", "required": true]]]), "UNRESOLVED_INPUT")
    }

    func testUnresolvedAndSensitiveCaptureFailuresPrecedeRendererAdmission() {
        let fill: Body = ["action": "fill", "target": ["label": "Password"], "text": "fixture-only", "sensitive": true]
        assertRejected(workflow([tap, fill, ["action": "screenshot"]]), "SENSITIVE_CAPTURE_REFUSED")
        assertRejected(workflow([fill], ["capture": ["formats": ["gif"]]]), "SENSITIVE_CAPTURE_REFUSED")
        assertRejected(workflow([tap, fill.merging(["text": ["secret": "private"]]) { _, new in new }]), "UNRESOLVED_INPUT")
    }

    func testSuppliedCaptureDefaultsAndExplicitScreenshotScope() throws {
        let one = try ScriptBoundWorkflow(workflow([tap, ["action": "screenshot"]]))
        XCTAssertFalse(one.stepScreenshots)
        XCTAssertEqual(one.capture?["formats"] as? [String], ["screenshots"])
        let every = try ScriptBoundWorkflow(workflow([tap], ["capture": ["formats": ["screenshots"], "maxBytes": 1024]]))
        XCTAssertTrue(every.stepScreenshots)
        XCTAssertEqual(every.capture?["maxBytes"] as? Int, 1024)
    }

    @MainActor
    func testLateMutatingRendererCallbackRetiresBeforeFurtherAdmission() async throws {
        let renderer = WKWebViewRenderer()
        let lease = BrowserControlLease()
        var complete: CheckedContinuation<Bool, Never>?
        do {
            _ = try await ScriptRendererDeadline.run(renderer: renderer, seconds: 1, mutates: true, lease: lease) {
                await withCheckedContinuation { complete = $0 }
            }
            XCTFail("Timed-out renderer operation returned success")
        } catch let failure as ScriptWorkflowFailure {
            XCTAssertEqual(failure.code, "TIMEOUT")
            XCTAssertTrue(failure.mayHaveCompleted)
        }
        XCTAssertTrue(ScriptRendererDeadline.isRetiring(renderer))
        XCTAssertFalse(lease.begin())
        let late = try XCTUnwrap(complete)
        late.resume(returning: true)
        for _ in 0..<20 where ScriptRendererDeadline.isRetiring(renderer) { await Task.yield() }
        XCTAssertFalse(ScriptRendererDeadline.isRetiring(renderer))
        XCTAssertTrue(lease.begin())
        lease.end()
    }

    func testIndependentGrantsAndListenerIncarnationsCannotInheritRuns() {
        let listener = ScriptListenerScope()
        let first = listener.start()
        let original = ScriptRequestOwner(listener: first, clientID: "client", bearer: "test-first", isCurrent: { true })
        let replacement = ScriptRequestOwner(listener: first, clientID: "client", bearer: "test-second", isCurrent: { true })
        let second = listener.start()
        let restarted = ScriptRequestOwner(listener: second, clientID: "client", bearer: "test-first", isCurrent: { true })
        listener.stop(first)
        XCTAssertEqual(listener.incarnation, second)
        XCTAssertNotEqual(original.owner, replacement.owner)
        XCTAssertNotEqual(original.owner, restarted.owner)
        XCTAssertFalse(original.owner.contains("test-first"))
        listener.stop(second)
        XCTAssertNil(listener.incarnation)
    }
}
