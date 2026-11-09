import Foundation

/// Agent-facing cookie dates. The automation API documents `expires` as ISO 8601 UTC
/// (`2026-04-30T00:00:00.000Z`) or null; the peer-to-peer sync wire uses whole Unix
/// seconds. These helpers convert at the API boundary so neither format leaks into the
/// other.
public enum CookieAPIFormat {
    nonisolated(unsafe) private static let withMilliseconds: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    nonisolated(unsafe) private static let withoutMilliseconds = ISO8601DateFormatter()

    /// `expires` for API output.
    public static func expires(_ date: Date?) -> Any {
        date.map { withMilliseconds.string(from: $0) } ?? NSNull()
    }

    /// A wire-shape cookie (Unix-second `expires`) as API output.
    public static func apiJSON(fromWire wire: [String: Any]) -> [String: Any] {
        var api = wire
        if let seconds = SyncJSON.int64(wire["expires"]) {
            api["expires"] = expires(Date(timeIntervalSince1970: TimeInterval(seconds)))
        }
        return api
    }

    /// An API cookie as wire shape: `expires` may be ISO 8601 (with or without
    /// milliseconds), whole Unix seconds or null. nil when `expires` is anything else.
    public static func wireJSON(fromAPI api: [String: Any]) -> [String: Any]? {
        var wire = api
        switch api["expires"] {
        case nil, is NSNull:
            wire["expires"] = NSNull()
        case let text as String:
            guard let date = withMilliseconds.date(from: text) ?? withoutMilliseconds.date(from: text) else { return nil }
            wire["expires"] = NSNumber(value: Int64(date.timeIntervalSince1970.rounded(.down)))
        case let raw:
            guard let seconds = SyncJSON.int64(raw) else { return nil }
            wire["expires"] = NSNumber(value: seconds)
        }
        return wire
    }
}
