import Foundation

@main
struct ScriptRedactionAcceptance {
    static func require(_ condition: @autoclosure () -> Bool, _ name: String) throws {
        guard condition() else { throw NSError(domain: "ScriptRedactionAcceptance", code: 1, userInfo: [NSLocalizedDescriptionKey: name]) }
    }

    static func main() throws {
        for (input, expected) in [
            ("Aa%20b%2b!", "[redacted]"), ("Aa+b%2b%21", "[redacted]"),
            ("Aa%20b%2B!", "[redacted]"), ("aa b+!", "aa b+!"), ("Aa%20B%2b!", "Aa%20B%2b!")
        ] {
            let result = try ScriptOutputRedaction.redact(["value": input], actions: [], secrets: ["Aa b+!"])
            try require(result["value"] as? String == expected, "Percent hex representation parity")
        }
        for (input, expected) in [
            ("token%2FValue", "[redacted]"), ("token%252FValue", "[redacted]"), ("token%2fValue", "token%2fValue")
        ] {
            let result = try ScriptOutputRedaction.redact(["value": input], actions: [], secrets: ["token%2FValue"])
            try require(result["value"] as? String == expected, "Raw percent literal remains case sensitive")
        }
        let actions: [[String: Any]] = [["action": "extract", "name": "cards"], ["action": "fill", "text": "not copied to native request"]]
        let extraction: [String: Any] = [
            "url": "https://fixture/text",
            "documentRevision": ["availability": "unavailable"],
            "fields": [["name": "text", "status": "ok", "values": ["text ok publisher-claim"],
                        "provenance": ["selector": ".text", "source": "text", "matches": 1]]],
            "metadata": [["key": "publisher-claim", "value": "publisher-claim", "authority": "publisher-claim"]]
        ]
        let value = try ScriptOutputRedaction.redact(["cards": extraction], actions: actions, secrets: ["text", "ok", "publisher-claim"])
        guard let cards = value["cards"] as? [String: Any],
              let field = (cards["fields"] as? [[String: Any]])?.first,
              let metadata = (cards["metadata"] as? [[String: Any]])?.first else { throw ScriptOutputRedaction.Failure.invalid }
        try require(field["status"] as? String == "ok", "Trusted extraction enum")
        try require(field["name"] as? String == "[redacted]", "Page-derived name")
        try require((field["provenance"] as? [String: Any])?["source"] as? String == "text", "Trusted source enum")
        try require(metadata["authority"] as? String == "publisher-claim", "Metadata authority")
        try require(metadata["value"] as? String == "[redacted]", "Page-derived metadata")
        do {
            _ = try ScriptOutputRedaction.redact(["run": "one", "error": "two"], actions: [], secrets: ["run", "error"])
            throw ScriptOutputRedaction.Failure.invalid
        } catch ScriptOutputRedaction.Failure.collision {}
        do {
            _ = try ScriptOutputRedaction.redact(["value": String(repeating: "x", count: 262145)], actions: [], secrets: ["canary"])
            throw ScriptOutputRedaction.Failure.invalid
        } catch ScriptOutputRedaction.Failure.limit {}
        do {
            _ = try ScriptOutputRedaction.redact([:], actions: [["action": "extract", "name": "same"], ["action": "extract", "name": "same"]], secrets: [])
            throw ScriptOutputRedaction.Failure.limit
        } catch ScriptOutputRedaction.Failure.invalid {}
        for _ in 0..<1000 {
            let result = try ScriptOutputRedaction.redact(["out": "redacted e"], actions: [], secrets: ["redacted", "e"])
            try require(result["out"] as? String == "[redacted] [redacted]", "Repeated allocation/free and one-pass replacement")
        }
        print("PASS Swift -> shared C ABI: typed extraction, dynamic collision, encoded/raw case, bounds, fixed errors, 1000 owned allocations/free")
    }
}
