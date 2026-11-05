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

    func testPacedEditsPlanBeforeAdmissionAndKeepAtomicDefault() throws {
        let fill: Body = ["action": "fill", "target": ["label": "Draft"], "text": "A😀e\u{301}", "typingDelayMs": 50]
        let type: Body = ["action": "type", "target": ["label": "Draft"], "text": "xy", "typingDelayMs": 20]
        let plan = try ScriptBoundWorkflow(workflow([tap, fill, type]))
        let fillOps = try XCTUnwrap(plan.pacedPlans[1]).operations
        XCTAssertEqual(fillOps.map(\.action), ["fill", "type", "type", "type", "type"])
        XCTAssertEqual(fillOps.map(\.text), ["", "A", "😀", "e", "\u{301}"])
        XCTAssertEqual(fillOps.map(\.delayBeforeMs), [0, 0, 50, 50, 50])
        XCTAssertEqual(fillOps.map(\.requireFocused), [false, true, true, true, true])
        let typeOps = try XCTUnwrap(plan.pacedPlans[2]).operations
        XCTAssertEqual(typeOps.map(\.delayBeforeMs), [0, 20])
        XCTAssertEqual(typeOps.map(\.requireFocused), [false, true])
        let atomic = try ScriptBoundWorkflow(workflow([["action": "type", "target": ["label": "Draft"], "text": "xy"]]))
        XCTAssertTrue(atomic.pacedPlans.isEmpty)
        let emptyType = try ScriptBoundWorkflow(workflow([type.merging(["text": ""]) { _, new in new }]))
        XCTAssertTrue(try XCTUnwrap(emptyType.pacedPlans[0]).operations.isEmpty)
        let emptyFill = try ScriptBoundWorkflow(workflow([fill.merging(["text": ""]) { _, new in new }]))
        XCTAssertEqual(try XCTUnwrap(emptyFill.pacedPlans[0]).operations.map(\.action), ["fill"])
        let oversized = type.merging(["text": String(repeating: "a", count: 1001)]) { _, new in new }
        assertRejected(workflow([tap, oversized]), "INVALID_PACED_TYPING")
        let tooLong = type.merging(["text": String(repeating: "a", count: 1000), "typingDelayMs": 61]) { _, new in new }
        assertRejected(workflow([tap, tooLong]), "INVALID_PACED_TYPING")
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

    @MainActor
    func testMalformedCallbackLatchesPrivacyBeforeLaterGuardFailure() async {
        for captures in [true, false] {
            for value: Any? in [nil, "malformed", [1, 2], ["sensitivityKnown": true]] {
                let privacy = ScriptWorkflowPrivacy(secrets: [], captures: captures)
                do {
                    ScriptWorkflowTab.consumeTargetResult(
                        value,
                        consume: { privacy.consume($0, text: "canary") },
                        uncertain: { privacy.uncertain(text: "canary") }
                    )
                    await Task.yield()
                    throw ScriptWorkflowFailure("DOCUMENT_CHANGED", mayHaveCompleted: true)
                } catch let failure as ScriptWorkflowFailure {
                    XCTAssertEqual(failure.code, "DOCUMENT_CHANGED")
                    XCTAssertTrue(failure.mayHaveCompleted)
                } catch { XCTFail("Unexpected guard error") }
                XCTAssertEqual(privacy.secrets, ["canary"])
                XCTAssertEqual(privacy.discardMedia, captures)
            }
        }
        let known = ScriptWorkflowPrivacy(secrets: [], captures: true)
        ScriptWorkflowTab.consumeTargetResult(["sensitive": false, "sensitivityKnown": true],
                                              consume: { known.consume($0, text: "ordinary") },
                                              uncertain: { known.uncertain(text: "ordinary") })
        XCTAssertTrue(known.secrets.isEmpty)
        XCTAssertFalse(known.discardMedia)
        let unknown = ScriptWorkflowPrivacy(secrets: [], captures: true)
        unknown.consume(["sensitive": false, "sensitivityKnown": false], text: "canary")
        XCTAssertEqual(unknown.secrets, ["canary"])
        XCTAssertTrue(unknown.discardMedia)
        let sensitive = ScriptWorkflowPrivacy(secrets: [], captures: true)
        sensitive.consume(["sensitive": true, "sensitivityKnown": false], text: "canary")
        XCTAssertEqual(sensitive.secrets, ["canary"])
        XCTAssertTrue(sensitive.discardMedia)
    }

    @MainActor
    func testOwnedFocusNeverRunsForBackgroundWindow() {
        var calls = 0
        XCTAssertFalse(ScriptWorkflowTab.requestOwnedEditFocus(isKey: false) { calls += 1; return true })
        XCTAssertEqual(calls, 0)
        XCTAssertTrue(ScriptWorkflowTab.requestOwnedEditFocus(isKey: true) { calls += 1; return true })
        XCTAssertEqual(calls, 1)
        XCTAssertFalse(ScriptWorkflowTab.requestOwnedEditFocus(isKey: true) { calls += 1; return false })
        XCTAssertEqual(calls, 2)
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
