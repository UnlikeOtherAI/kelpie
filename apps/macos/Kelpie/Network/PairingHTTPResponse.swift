import Foundation

/// Helper to render HTTP responses with consistent headers.
///
/// No `Access-Control-Allow-Origin` is ever emitted — CLI fetch is not a
/// browser and the design removes CORS entirely. `noStore` adds the
/// `Cache-Control: no-store, no-cache` + `Pragma: no-cache` headers required
/// on `/v1/pair` and `/v1/pair/status` responses.
struct PairingHTTPResponse {
    let status: Int
    let body: Data
    let contentType: String
    let noStore: Bool

    init(status: Int, body: Data, contentType: String, noStore: Bool = false) {
        self.status = status
        self.body = body
        self.contentType = contentType
        self.noStore = noStore
    }

    static func json(status: Int, json: [String: Any], noStore: Bool = false) -> Self {
        let body = (try? JSONSerialization.data(withJSONObject: json)) ?? Data("{}".utf8)
        return Self(status: status, body: body, contentType: "application/json", noStore: noStore)
    }

    static func error(status: Int, code: String, message: String) -> Self {
        Self.json(status: status, json: ["success": false, "error": ["code": code, "message": message]])
    }

    static func malformed() -> Self {
        Self.error(status: 400, code: "BAD_REQUEST", message: "Malformed HTTP request")
    }

    static func healthOk() -> Self {
        Self(status: 200, body: Data(#"{"status":"ok"}"#.utf8), contentType: "application/json")
    }

    func render() -> Data {
        let statusText: String
        switch status {
        case 200: statusText = "OK"
        case 202: statusText = "Accepted"
        case 400: statusText = "Bad Request"
        case 401: statusText = "Unauthorized"
        case 403: statusText = "Forbidden"
        case 404: statusText = "Not Found"
        case 408: statusText = "Request Timeout"
        case 411: statusText = "Length Required"
        case 413: statusText = "Payload Too Large"
        case 415: statusText = "Unsupported Media Type"
        case 431: statusText = "Request Header Fields Too Large"
        case 500: statusText = "Internal Server Error"
        default: statusText = "Unknown"
        }
        var header = "HTTP/1.1 \(status) \(statusText)\r\n"
        header += "Content-Type: \(contentType)\r\n"
        header += "Content-Length: \(body.count)\r\n"
        if noStore {
            header += "Cache-Control: no-store, no-cache\r\n"
            header += "Pragma: no-cache\r\n"
        }
        header += "Connection: close\r\n\r\n"
        var response = Data(header.utf8)
        response.append(body)
        return response
    }
}
