import Network
import WebKit
import XCTest
@testable import Kelpie

final class ScriptWorkflowAdmissionTests: XCTestCase {
    typealias Body = [String: Any]
    private let tap: Body = ["action": "tap", "target": ["role": "button", "name": "Submit"]]

    @MainActor
    func testBonjourTXTReplacementKeepsSameHTTPListenerReachable() async throws {
        let port: UInt16 = 28421
        let router = Router()
        let server = try HTTPServer(port: port, router: router, pairingStore: PairingStore(),
                                    deviceInfo: DeviceInfo.current(port: Int(port)))
        let ready = expectation(description: "owned listener ready")
        server.onReady = { ready.fulfill() }
        server.start()
        defer { server.stop() }
        await fulfillment(of: [ready], timeout: 10)
        let serviceName = "Kelpie CI " + UUID().uuidString
        server.configureBonjourService(name: serviceName, type: "_kelpie._tcp", txtRecord: NWTXTRecord(["engine": "webkit"]))
        let first = try await Self.probeHTTP(port: port)
        server.configureBonjourService(name: serviceName, type: "_kelpie._tcp", txtRecord: NWTXTRecord(["engine": "chromium"]))
        try await Task.sleep(nanoseconds: 500_000_000)
        let second = try await Self.probeHTTP(port: port)
        XCTAssertEqual(first, second)
    }

    private static func probeHTTP(port: UInt16) async throws -> Int {
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        var request = URLRequest(url: try XCTUnwrap(URL(string: "http://127.0.0.1:\(port)/health")))
        request.timeoutInterval = 3
        request.setValue("close", forHTTPHeaderField: "Connection")
        let (_, response) = try await session.data(for: request)
        return try XCTUnwrap((response as? HTTPURLResponse)?.statusCode)
    }

    @MainActor
    func testEmptyPacedTypeRequiresEditableTarget() throws {
        try ScriptWorkflowActions.requireEmptyPacedEditable(["editable": true])
        for value: Any? in [false, nil] {
            var target: Body = [:]
            target["editable"] = value
            XCTAssertThrowsError(try ScriptWorkflowActions.requireEmptyPacedEditable(target)) {
                XCTAssertEqual(($0 as? ScriptWorkflowFailure)?.code, "TARGET_NOT_EDITABLE")
            }
        }
    }

    func testScrollbarTransitionAndProjection() {
        func viewport(client: CGFloat, visible: CGFloat, bounds: CGFloat = 900, scale: CGFloat = 1) -> ScriptCaptureViewport {
            ScriptCaptureViewport(bounds: CGSize(width: bounds, height: 700), layout: CGSize(width: 900, height: 700),
                client: CGSize(width: client, height: 700), visible: CGRect(x: 0, y: 0, width: visible, height: 700),
                scale: scale, pixelRatio: 1, pageOrigin: .zero)
        }
        XCTAssertFalse(ScriptCaptureViewport.confirmedDocumentChange(previous: nil, current: "new"))
        XCTAssertFalse(ScriptCaptureViewport.confirmedDocumentChange(previous: "", current: "new"))
        XCTAssertFalse(ScriptCaptureViewport.confirmedDocumentChange(previous: "old", current: ""))
        XCTAssertFalse(ScriptCaptureViewport.confirmedDocumentChange(previous: "old", current: "old"))
        XCTAssertTrue(ScriptCaptureViewport.confirmedDocumentChange(previous: "old", current: "new"))
        let scrollbar = viewport(client: 883, visible: 883), plain = viewport(client: 900, visible: 900)
        XCTAssertEqual(scrollbar.displayPoint(CGPoint(x: 860, y: 100)).x, 860)
        XCTAssertTrue(scrollbar.acceptsScrollbarTransition(to: plain, documentChanged: true))
        XCTAssertFalse(scrollbar.acceptsScrollbarTransition(to: plain, documentChanged: false))
        XCTAssertFalse(scrollbar.acceptsScrollbarTransition(to: viewport(client: 900, visible: 890), documentChanged: true))
        XCTAssertFalse(scrollbar.acceptsScrollbarTransition(to: viewport(client: 900, visible: 900, bounds: 901), documentChanged: true))
        XCTAssertFalse(scrollbar.acceptsScrollbarTransition(to: viewport(client: 900, visible: 900, scale: 2), documentChanged: true))
    }

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
            for value: Any? in [nil, "malformed", [1, 2], ["sensitivityKnown": true],
                                ["ok": true, "sensitive": false, "sensitivityKnown": true],
                                ["ok": true, "mayHaveCompleted": false, "sensitive": false, "sensitivityKnown": true]] {
                let privacy = ScriptWorkflowPrivacy(secrets: [], captures: captures)
                do {
                    ScriptWorkflowTab.consumeTargetResult(
                        value,
                        mutates: true,
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
    func testCanonicalMutationReceiptAndPrivacyFixture() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let data = try Data(contentsOf: root.appendingPathComponent("tests/capture/ack-receipt-cases.json"))
        let fixture = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? Body)
        let expectedToken = try XCTUnwrap(fixture["expectedToken"] as? String)
        let cases = try XCTUnwrap(fixture["cases"] as? [Body])
        XCTAssertEqual(cases.count, 52)
        for item in cases {
            let name = try XCTUnwrap(item["name"] as? String)
            let result = item["result"]
            let body = result as? Body
            let valid = body.map { ScriptWorkflowTab.hasValidMutationReceipt($0) } ?? false
            let acknowledged = ScriptWorkflowTab.isAcknowledgedMutation(result, token: expectedToken)
            let refused = valid && ScriptWorkflowBoolean.value(body?["ok"]) == false
            let receipt = acknowledged ? "ack" : refused ? "refusal" : "malformed"
            XCTAssertEqual(receipt, item["expectedReceipt"] as? String, name)
            let privacy = ScriptWorkflowPrivacy(secrets: [], captures: true)
            ScriptWorkflowTab.consumeTargetResult(
                result, mutates: true, expectedToken: expectedToken,
                consume: { privacy.consume($0, text: "literal") },
                uncertain: { privacy.uncertain(text: "literal") }
            )
            let protected = item["expectedPrivacy"] as? String != "known-negative"
            XCTAssertEqual(privacy.discardMedia, protected, name)
            XCTAssertEqual(privacy.secrets, protected ? ["literal"] : [], name)
        }
    }

    @MainActor
    func testJSONReceiptBooleansRejectNumbersStringsAndNull() throws {
        func decoded(_ json: String) throws -> Body {
            try XCTUnwrap(JSONSerialization.jsonObject(with: Data(json.utf8)) as? Body)
        }
        let good = try decoded(#"{"token":"expected","ok":true,"mayHaveCompleted":true,"sensitive":false,"sensitivityKnown":true,"inputGuarantee":"synthetic-coordinate"}"#)
        XCTAssertTrue(ScriptWorkflowTab.isAcknowledgedMutation(good, token: "expected"))
        var emptyError = good
        emptyError["ok"] = false
        emptyError["error"] = ""
        XCTAssertFalse(ScriptWorkflowTab.hasValidMutationReceipt(emptyError))
        for field in ["ok", "mayHaveCompleted", "sensitive", "sensitivityKnown"] {
            for raw in ["1", "0", #""true""#, "null"] {
                var candidate = good
                candidate[field] = try decoded("{\"value\":\(raw)}")["value"]
                XCTAssertFalse(ScriptWorkflowTab.isAcknowledgedMutation(candidate, token: "expected"))
                XCTAssertThrowsError(try ScriptWorkflowActions.requirePacedAckShape(candidate))
                let privacy = ScriptWorkflowPrivacy(secrets: [], captures: true)
                ScriptWorkflowTab.consumeTargetResult(candidate, mutates: true, expectedToken: "expected",
                    consume: { privacy.consume($0, text: "full literal") },
                    uncertain: { privacy.uncertain(text: "full literal") })
                XCTAssertEqual(privacy.secrets, ["full literal"])
                XCTAssertTrue(privacy.discardMedia)
            }
        }
        for raw in ["1", "0", #""true""#, "null"] {
            let candidate = try decoded("{\"editable\":\(raw)}")
            XCTAssertThrowsError(try ScriptWorkflowActions.requireEmptyPacedEditable(candidate))
        }
        for raw in ["1", "0", #""true""#, "null"] {
            let privacy = ScriptWorkflowPrivacy(secrets: [], captures: true)
            let candidate = try decoded("{\"sensitive\":false,\"sensitivityKnown\":\(raw)}")
            privacy.consume(candidate, text: "full literal")
            XCTAssertEqual(privacy.secrets, ["full literal"])
            XCTAssertTrue(privacy.discardMedia)
        }
    }

    @MainActor
    func testFinalPacedAckDistinguishesUnknownPrivacyFromLostCallback() throws {
        let known: Body = ["token": "expected", "inputGuarantee": "synthetic-coordinate", "ok": true, "mayHaveCompleted": true, "sensitive": false, "sensitivityKnown": true]
        let unknown: Body = ["token": "expected", "inputGuarantee": "synthetic-coordinate", "ok": true, "mayHaveCompleted": true, "sensitive": false, "sensitivityKnown": false]
        XCTAssertTrue(ScriptWorkflowTab.isAcknowledgedMutation(known, token: "expected"))
        XCTAssertTrue(ScriptWorkflowTab.isAcknowledgedMutation(unknown, token: "expected"))
        var emptyToken = known
        emptyToken["token"] = ""
        XCTAssertFalse(ScriptWorkflowTab.isAcknowledgedMutation(emptyToken, token: ""))
        for guarantee: Any? in [nil, "other"] {
            var invalid = known
            invalid["inputGuarantee"] = guarantee
            XCTAssertFalse(ScriptWorkflowTab.isAcknowledgedMutation(invalid, token: "expected"))
            XCTAssertThrowsError(try ScriptWorkflowActions.requirePacedAckShape(invalid))
        }
        var uncertaintyCount = 0
        XCTAssertTrue(ScriptWorkflowTab.acceptAcknowledgedDocumentChange(known, token: "expected", editing: false) { uncertaintyCount += 1 })
        XCTAssertEqual(uncertaintyCount, 0)
        XCTAssertTrue(ScriptWorkflowTab.acceptAcknowledgedDocumentChange(known, token: "expected", editing: true) { uncertaintyCount += 1 })
        XCTAssertEqual(uncertaintyCount, 1)
        XCTAssertFalse(ScriptWorkflowTab.acceptAcknowledgedDocumentChange(nil, token: "expected", editing: false) { uncertaintyCount += 1 })
        XCTAssertEqual(uncertaintyCount, 1)
        XCTAssertFalse(ScriptWorkflowTab.acceptAcknowledgedDocumentChange(known, token: "other", editing: true) { uncertaintyCount += 1 })
        XCTAssertEqual(uncertaintyCount, 1)
        let mismatched = ScriptWorkflowPrivacy(secrets: [], captures: true)
        ScriptWorkflowTab.consumeTargetResult(known, mutates: true, expectedToken: "other",
            consume: { mismatched.consume($0, text: "full literal") }, uncertain: { mismatched.uncertain(text: "full literal") })
        XCTAssertEqual(mismatched.secrets, ["full literal"])
        XCTAssertTrue(mismatched.discardMedia)
        for malformed: Any? in [nil, "missing", [:], ["ok": true, "sensitive": false, "sensitivityKnown": false],
                                ["ok": false, "mayHaveCompleted": true, "sensitive": false, "sensitivityKnown": false],
                                ["ok": true, "error": "bad", "mayHaveCompleted": true, "sensitive": false, "sensitivityKnown": false],
                                ["ok": true, "mayHaveCompleted": false, "sensitive": false, "sensitivityKnown": true]] {
            XCTAssertFalse(ScriptWorkflowTab.isAcknowledgedMutation(malformed, token: "expected"))
        }
        try ScriptWorkflowActions.requirePacedAckShape(known)
        try ScriptWorkflowActions.requirePacedAckShape(unknown)
        var positiveUnknown = unknown
        positiveUnknown["sensitive"] = true
        try ScriptWorkflowActions.requirePacedClassification(positiveUnknown, hasFurther: true, discardMedia: false)
        XCTAssertThrowsError(try ScriptWorkflowActions.requirePacedClassification(positiveUnknown, hasFurther: true, discardMedia: true)) {
            XCTAssertEqual(($0 as? ScriptWorkflowFailure)?.code, "SENSITIVE_CAPTURE_REFUSED")
        }
        XCTAssertThrowsError(try ScriptWorkflowActions.requirePacedAckShape(["ok": true, "sensitive": false])) {
            let failure = $0 as? ScriptWorkflowFailure
            XCTAssertEqual(failure?.code, "INPUT_UNCERTAIN")
            XCTAssertEqual(failure?.mayHaveCompleted, true)
        }
        for captures in [true, false] {
            let privacy = ScriptWorkflowPrivacy(secrets: [], captures: captures)
            privacy.consume(known, text: "full literal")
            XCTAssertTrue(privacy.secrets.isEmpty)
            XCTAssertFalse(privacy.discardMedia)
            privacy.consume(unknown, text: "full literal")
            XCTAssertEqual(privacy.secrets, ["full literal"])
            XCTAssertEqual(privacy.discardMedia, captures)
            let redacted = try ScriptOutputRedaction.redact(["before": "full literal"], actions: [], secrets: privacy.secrets)
            XCTAssertEqual(redacted["before"] as? String, "[redacted]")
            if captures {
                XCTAssertThrowsError(try ScriptWorkflowActions.requirePacedClassification(unknown, hasFurther: false, discardMedia: true)) {
                    XCTAssertEqual(($0 as? ScriptWorkflowFailure)?.code, "SENSITIVE_CAPTURE_REFUSED")
                }
            } else {
                try ScriptWorkflowActions.requirePacedClassification(unknown, hasFurther: false, discardMedia: false)
                XCTAssertThrowsError(try ScriptWorkflowActions.requirePacedClassification(unknown, hasFurther: true, discardMedia: false)) {
                    let failure = $0 as? ScriptWorkflowFailure
                    XCTAssertEqual(failure?.code, "INPUT_UNCERTAIN")
                    XCTAssertEqual(failure?.mayHaveCompleted, true)
                }
            }
        }
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
