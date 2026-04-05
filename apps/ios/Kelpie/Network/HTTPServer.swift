import Foundation
import Network

/// Embedded HTTP server for receiving CLI commands.
/// Uses raw NWListener since we want zero external dependencies for the server.
final class HTTPServer: @unchecked Sendable {
    let port: UInt16
    let router: Router
    private var listener: NWListener?

    init(port: UInt16 = 8420, router: Router) {
        self.port = port
        self.router = router
    }

    func start() {
        do {
            let params = NWParameters.tcp
            params.allowLocalEndpointReuse = true
            listener = try NWListener(using: params, on: NWEndpoint.Port(rawValue: port)!)
        } catch {
            print("[HTTPServer] Failed to create listener: \(error)")
            return
        }

        listener?.newConnectionHandler = { [weak self] connection in
            self?.handleConnection(connection)
        }
        listener?.stateUpdateHandler = { state in
            switch state {
            case .ready:
                print("[HTTPServer] Listening on port \(self.port)")
            case .failed(let error):
                print("[HTTPServer] Listener failed: \(error)")
            default:
                break
            }
        }
        listener?.start(queue: .global(qos: .userInitiated))
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: .global(qos: .userInitiated))
        receiveData(connection: connection, buffer: Data())
    }

    private func receiveData(connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] content, _, isComplete, error in
            guard let self else { return }
            var accumulated = buffer
            if let content { accumulated.append(content) }

            if isComplete || error != nil {
                Task {
                    await self.processRequest(connection: connection, data: accumulated)
                }
            } else if let headerEnd = accumulated.range(of: Data("\r\n\r\n".utf8)) {
                let headerString = String(data: accumulated[..<headerEnd.lowerBound], encoding: .utf8) ?? ""
                let contentLength = self.parseContentLength(headerString)
                let bodyStart = headerEnd.upperBound
                let bodyReceived = accumulated.distance(from: bodyStart, to: accumulated.endIndex)

                if bodyReceived >= contentLength {
                    Task {
                        await self.processRequest(connection: connection, data: accumulated)
                    }
                } else {
                    self.receiveData(connection: connection, buffer: accumulated)
                }
            } else {
                self.receiveData(connection: connection, buffer: accumulated)
            }
        }
    }

    private func parseContentLength(_ headers: String) -> Int {
        for line in headers.components(separatedBy: "\r\n") {
            if line.lowercased().hasPrefix("content-length:") {
                let value = line.dropFirst("content-length:".count).trimmingCharacters(in: .whitespaces)
                return Int(value) ?? 0
            }
        }
        return 0
    }

    private func processRequest(connection: NWConnection, data: Data) async {
        let raw = String(data: data, encoding: .utf8) ?? ""
        let (requestLine, body) = parseHTTPRequest(raw)
        let parts = requestLine.split(separator: " ")
        let httpMethod = parts.first.map(String.init) ?? "GET"
        let path = parts.count > 1 ? String(parts[1]) : "/"

        var statusCode = 200
        var responseBody: [String: Any]

        if httpMethod == "POST", path.hasPrefix("/v1/") {
            let method = String(path.dropFirst("/v1/".count))
            let jsonBody = parseJSON(body)
            let (code, result) = await router.handle(method: method, body: jsonBody)
            statusCode = code
            responseBody = result
        } else if path == "/health" {
            responseBody = ["status": "ok"]
        } else {
            statusCode = 404
            responseBody = ["error": "Not found"]
        }

        let jsonData = (try? JSONSerialization.data(withJSONObject: responseBody)) ?? Data("{}".utf8)
        let response = buildHTTPResponse(statusCode: statusCode, body: jsonData)
        connection.send(content: response, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private func parseHTTPRequest(_ raw: String) -> (requestLine: String, body: String) {
        guard let headerEnd = raw.range(of: "\r\n\r\n") else {
            return (raw.components(separatedBy: "\r\n").first ?? "", "")
        }
        let requestLine = raw[..<headerEnd.lowerBound].components(separatedBy: "\r\n").first ?? ""
        let body = String(raw[headerEnd.upperBound...])
        return (requestLine, body)
    }

    private func parseJSON(_ body: String) -> [String: Any] {
        guard !body.isEmpty,
              let data = body.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        return json
    }

    private func buildHTTPResponse(statusCode: Int, body: Data) -> Data {
        let statusText: String
        switch statusCode {
        case 200: statusText = "OK"
        case 400: statusText = "Bad Request"
        case 404: statusText = "Not Found"
        case 500: statusText = "Internal Server Error"
        default: statusText = "Unknown"
        }
        let header = """
        HTTP/1.1 \(statusCode) \(statusText)\r
        Content-Type: application/json\r
        Content-Length: \(body.count)\r
        Access-Control-Allow-Origin: *\r
        Connection: close\r
        \r

        """
        var response = Data(header.utf8)
        response.append(body)
        return response
    }
}
