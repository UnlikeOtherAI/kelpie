import Foundation

/// Unpadded base64url, the encoding of every binary field in the sync protocol.
enum Base64URL {
    static func encode(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    static func decode(_ text: String) -> Data? {
        guard text.unicodeScalars.allSatisfy(isAlphabet) else { return nil }
        var standard = text.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        let remainder = standard.count % 4
        if remainder == 1 { return nil }
        if remainder > 0 { standard += String(repeating: "=", count: 4 - remainder) }
        return Data(base64Encoded: standard)
    }

    private static func isAlphabet(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar {
        case "A"..."Z", "a"..."z", "0"..."9", "-", "_": return true
        default: return false
        }
    }
}

/// Compact JSON helpers for core-sync's string interface.
enum SyncJSON {
    static func object(_ text: String) -> [String: Any]? { object(Data(text.utf8)) }

    static func object(_ data: Data) -> [String: Any]? {
        (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    static func value(_ text: String) -> Any? {
        try? JSONSerialization.jsonObject(with: Data(text.utf8), options: [.fragmentsAllowed])
    }

    static func data(_ value: Any) throws -> Data {
        try JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed, .withoutEscapingSlashes])
    }

    static func string(_ value: Any) -> String {
        guard let data = try? data(value) else { return "null" }
        return String(bytes: data, encoding: .utf8) ?? "null"
    }

    /// A JSON integer, never a boolean or a fraction.
    static func int64(_ value: Any?) -> Int64? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        let integer = number.int64Value
        return Double(integer) == number.doubleValue ? integer : nil
    }

    static func uint64(_ value: Any?) -> UInt64? {
        guard let integer = int64(value), integer >= 0 else { return nil }
        return UInt64(integer)
    }

    /// A JSON boolean; absent and null read as `fallback`, anything else is invalid.
    static func flag(_ value: Any?, fallback: Bool = false) -> Bool? {
        switch value {
        case nil, is NSNull: return fallback
        case let number as NSNumber where CFGetTypeID(number) == CFBooleanGetTypeID(): return number.boolValue
        default: return nil
        }
    }
}
