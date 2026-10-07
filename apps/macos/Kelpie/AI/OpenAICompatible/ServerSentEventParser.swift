import Foundation

/// One dispatched server-sent event.
struct ServerSentEvent: Equatable, Sendable {
    let event: String?
    let data: String
}

/// Incremental, byte-oriented SSE parser (WHATWG event-stream rules).
///
/// Chunks may split anywhere — inside a field name, inside `data:`, inside a
/// multi-byte UTF-8 sequence, or between `\r` and `\n`. Bytes are buffered
/// until a full line is available and only complete lines are decoded.
struct ServerSentEventParser {
    private var lineBuffer: [UInt8] = []
    private var dataLines: [String] = []
    private var eventName: String?
    private var lastByteWasCR = false

    /// Feeds raw bytes and returns every event completed by them.
    mutating func feed<Bytes: Sequence>(_ bytes: Bytes) -> [ServerSentEvent] where Bytes.Element == UInt8 {
        var events: [ServerSentEvent] = []
        for byte in bytes {
            if lastByteWasCR {
                lastByteWasCR = false
                if byte == 0x0A { continue } // CRLF: line already ended at CR.
            }
            switch byte {
            case 0x0D:
                lastByteWasCR = true
                if let event = endLine() { events.append(event) }
            case 0x0A:
                if let event = endLine() { events.append(event) }
            default:
                lineBuffer.append(byte)
            }
        }
        return events
    }

    /// Flushes a trailing event when the stream closes without a blank line.
    mutating func finish() -> [ServerSentEvent] {
        var events: [ServerSentEvent] = []
        if !lineBuffer.isEmpty, let event = endLine() { events.append(event) }
        if let event = dispatch() { events.append(event) }
        return events
    }

    private mutating func endLine() -> ServerSentEvent? {
        let line = String(bytes: lineBuffer, encoding: .utf8) ?? "\u{FFFD}"
        lineBuffer.removeAll(keepingCapacity: true)
        if line.isEmpty { return dispatch() }
        if line.hasPrefix(":") { return nil } // comment / keep-alive

        let field: Substring
        var value: Substring
        if let colon = line.firstIndex(of: ":") {
            field = line[..<colon]
            value = line[line.index(after: colon)...]
            if value.hasPrefix(" ") { value = value.dropFirst() }
        } else {
            field = Substring(line)
            value = ""
        }
        switch field {
        case "data": dataLines.append(String(value))
        case "event": eventName = String(value)
        default: break // id, retry and unknown fields are not needed here
        }
        return nil
    }

    private mutating func dispatch() -> ServerSentEvent? {
        defer {
            dataLines.removeAll()
            eventName = nil
        }
        guard !dataLines.isEmpty else { return nil }
        return ServerSentEvent(event: eventName, data: dataLines.joined(separator: "\n"))
    }
}
