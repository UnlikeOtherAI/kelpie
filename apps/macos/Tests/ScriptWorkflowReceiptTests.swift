import Foundation
import XCTest
@testable import Kelpie

final class ScriptWorkflowReceiptTests: XCTestCase {
    typealias Body = [String: Any]

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

}
