import Foundation
import XCTest
@testable import Kelpie

final class ScriptOutputRedactionTests: XCTestCase {
    func testDynamicNamesAndUnknownNestedKeysAreScrubbed() throws {
        let outputs: [String: Any] = ["error": ["run": "run error"], "status": "complete"]
        let actions: [[String: Any]] = [["action": "output", "name": "status", "source": "status"]]
        let value = try ScriptOutputRedaction.redact(outputs, actions: actions, secrets: ["error", "run"])
        XCTAssertNil(value["error"])
        XCTAssertEqual((value["[redacted]"] as? [String: Any])?["[redacted]"] as? String, "[redacted] [redacted]")
        XCTAssertEqual(value["status"] as? String, "complete")
    }

    func testCanonicalExtractionKeepsOnlyTrustedStructureAndEnums() throws {
        let actions: [[String: Any]] = [["action": "extract", "name": "cards"]]
        let extraction: [String: Any] = [
            "url": "https://fixture/text",
            "documentRevision": ["availability": "unavailable"],
            "fields": [["name": "text", "status": "ok", "values": ["text ok publisher-claim"],
                        "provenance": ["selector": ".text", "source": "text", "matches": 1]]],
            "metadata": [["key": "publisher-claim", "value": "publisher-claim", "authority": "publisher-claim"]],
            "text": ["ok": "publisher-claim"]
        ]
        let value = try ScriptOutputRedaction.redact(["cards": extraction], actions: actions, secrets: ["text", "ok", "publisher-claim"])
        let cards = try XCTUnwrap(value["cards"] as? [String: Any])
        let field = try XCTUnwrap((cards["fields"] as? [[String: Any]])?.first)
        XCTAssertEqual(field["status"] as? String, "ok")
        XCTAssertEqual(field["name"] as? String, "[redacted]")
        XCTAssertEqual(field["values"] as? [String], ["[redacted] [redacted] [redacted]"])
        let provenance = try XCTUnwrap(field["provenance"] as? [String: Any])
        XCTAssertEqual(provenance["source"] as? String, "text")
        XCTAssertEqual(provenance["selector"] as? String, ".[redacted]")
        let metadata = try XCTUnwrap((cards["metadata"] as? [[String: Any]])?.first)
        XCTAssertEqual(metadata["authority"] as? String, "publisher-claim")
        XCTAssertEqual(metadata["value"] as? String, "[redacted]")
        XCTAssertNil(cards["text"])
    }

    func testDynamicCollisionRefusesWithoutOriginalKeys() {
        XCTAssertThrowsError(try ScriptOutputRedaction.redact(["run": "one", "error": "two"], actions: [], secrets: ["run", "error"])) {
            XCTAssertEqual($0 as? ScriptOutputRedaction.Failure, .collision)
        }
    }

    func testOriginalByteMatchingDoesNotRescanInsertedMarkers() throws {
        let value = try ScriptOutputRedaction.redact(["out": "redacted e"], actions: [], secrets: ["e", "redacted"])
        XCTAssertEqual(value["out"] as? String, "[redacted] [redacted]")
    }

    func testEncodedReflectionsAreScrubbedAndOversizedOutputRefuses() throws {
        let value = try ScriptOutputRedaction.redact(["value": "a%20b%2B! a+b%2B%21"], actions: [], secrets: ["a b+!"])
        XCTAssertEqual(value["value"] as? String, "[redacted] [redacted]")
        XCTAssertThrowsError(try ScriptOutputRedaction.redact(["value": String(repeating: "x", count: 262145)], actions: [], secrets: ["canary"])) {
            XCTAssertEqual($0 as? ScriptOutputRedaction.Failure, .limit)
        }
    }
    func testOnlyEncodedHexDigitsIgnoreCase() throws {
        let inputs = ["Aa%20b%2b!", "Aa+b%2b%21", "Aa%20b%2B!", "aa b+!", "Aa%20B%2b!"]
        let expected = ["[redacted]", "[redacted]", "[redacted]", "aa b+!", "Aa%20B%2b!"]
        for (input, output) in zip(inputs, expected) {
            let value = try ScriptOutputRedaction.redact(["value": input], actions: [], secrets: ["Aa b+!"])
            XCTAssertEqual(value["value"] as? String, output)
        }
        for (input, output) in [("token%2FValue", "[redacted]"), ("token%252FValue", "[redacted]"), ("token%2fValue", "token%2fValue")] {
            let value = try ScriptOutputRedaction.redact(["value": input], actions: [], secrets: ["token%2FValue"])
            XCTAssertEqual(value["value"] as? String, output)
        }
    }

}
