import AVFoundation
import CryptoKit
import ImageIO
import XCTest

/// The app is exercised over its paired loopback HTTP/MCP listener, exactly like a CLI client.
final class WorkflowCaptureProbe {
    typealias Body = [String: Any]
    let port: Int
    var token: String?
    init(port: Int) { self.port = port }

    func request(_ path: String, _ body: Body? = nil, method: String = "POST") async throws -> Body {
        let url = try XCTUnwrap(URL(string: "http://127.0.0.1:\(port)" + path))
        var request = URLRequest(url: url, timeoutInterval: 90)
        request.httpMethod = method
        if let token { request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization") }
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let (data, _) = try await URLSession.shared.data(for: request)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? Body)
    }

    @MainActor
    func pair(app: XCUIApplication) async throws {
        let pending = try await request("/v1/pair", ["clientId": UUID().uuidString, "clientName": "Workflow UI test"])
        let id = try XCTUnwrap(pending["requestId"] as? String)
        let allow = app.buttons["Yes, once"]
        XCTAssertTrue(allow.waitForExistence(timeout: 10))
        allow.tap()
        for _ in 0..<40 {
            let status = try await request("/v1/pair/status?requestId=" + id, method: "GET")
            if let issued = status["token"] as? String {
                token = issued
                let deadline = Date().addingTimeInterval(5)
                while allow.exists, Date() < deadline { try await Task.sleep(nanoseconds: 80_000_000) }
                XCTAssertFalse(allow.exists, "Approved pairing sheet must retire before the next app interaction")
                return
            }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        throw ProbeError.pairing
    }

    func call(_ tool: String, _ args: Body) async throws -> Body {
        let value = try await toolValue("kelpie_extension", ["name": tool, "arguments": args])
        return try XCTUnwrap(value as? Body)
    }

    func toolEnvelope(_ name: String, _ arguments: Body) async throws -> Body {
        let response = try await request("/mcp", ["jsonrpc": "2.0", "id": 1, "method": "tools/call", "params": [
            "name": name, "arguments": arguments
        ]])
        let result = try XCTUnwrap(response["result"] as? Body)
        let text = try XCTUnwrap((result["content"] as? [Body])?.first(where: { $0["type"] as? String == "text" })?["text"] as? String)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: Data(text.utf8)) as? Body)
    }

    func toolValue(_ name: String, _ arguments: Body) async throws -> Any {
        let envelope = try await toolEnvelope(name, arguments)
        if envelope["ok"] as? Bool != true {
            // Preserve only fixed error codes and action metadata; never attach page output.
            let status = try? await toolEnvelope("kelpie_get_script_status", [:])
            let value = status?["value"] as? Body
            let error = value?["runError"] as? Body
            let rawCode = error?["code"] as? String ?? "UNKNOWN"
            let code = rawCode.range(of: "^[A-Z0-9_]{1,80}$", options: .regularExpression) == nil ? "UNKNOWN" : rawCode
            let index = value?["actionIndex"] as? Int ?? -1
            XCTFail("MCP play failed; terminal code: \(code); action index: \(index)")
        }
        return try XCTUnwrap(envelope["value"])
    }

    func bytes(_ manifest: Body, run: String) async throws -> Data {
        let id = try XCTUnwrap(manifest["id"] as? String)
        let size = try XCTUnwrap(manifest["byteLength"] as? Int)
        var bytes = Data()
        while bytes.count < size {
            let range: Body = ["runId": run, "artifactId": id, "offset": bytes.count, "length": 32768]
            let chunk = bytes.isEmpty ? try await call("kelpie_get_script_artifact", range) :
                try await request("/v1/get-script-artifact", range)
            XCTAssertEqual(chunk["artifactId"] as? String, id)
            XCTAssertEqual(chunk["offset"] as? Int, bytes.count)
            let new = try XCTUnwrap((chunk["data"] as? String).flatMap { Data(base64Encoded: $0) })
            guard !new.isEmpty, bytes.count + new.count <= size else { throw ProbeError.invalidChunk }
            bytes.append(new)
        }
        XCTAssertEqual(SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined(), manifest["sha256"] as? String)
        return bytes
    }

    static func errorCode(_ value: Body) -> String {
        let code = (value["error"] as? Body)?["code"] as? String ?? "NONE"
        return code.range(of: "^[A-Z0-9_]{1,80}$", options: .regularExpression) == nil ? "UNKNOWN" : code
    }

    enum ProbeError: Error { case invalidChunk, pairing, listener }

    static func containsTargetMarker(_ screen: XCUIScreenshot, visibleTarget: CGRect, app: CGRect) -> Bool {
        guard !visibleTarget.isEmpty, !app.isEmpty, let image = screen.image.cgImage else { return false }
        let xScale = CGFloat(image.width) / app.width
        let yScale = CGFloat(image.height) / app.height
        let radius = min(12, visibleTarget.width / 3, visibleTarget.height / 3)
        let crop = CGRect(x: (visibleTarget.midX - app.minX - radius) * xScale,
                          y: (visibleTarget.midY - app.minY - radius) * yScale,
                          width: radius * 2 * xScale, height: radius * 2 * yScale)
        guard let center = image.cropping(to: crop.integral) else { return false }
        return containsMarker(center, minimumCoverage: 0.12)
    }

    static func containsMarker(_ image: CGImage, minimumCoverage: Double = 0) -> Bool {
        let width = min(200, image.width)
        let height = max(1, width * image.height / image.width)
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        return pixels.withUnsafeMutableBytes { raw in
            guard let ctx = CGContext(data: raw.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return false }
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            func green(_ pixel: Int) -> Bool {
                let index = 4 * pixel
                return raw[index + 1] > 155 && raw[index] < 90 && raw[index + 2] < 95
            }
            guard width >= 3, height >= 3 else { return false }
            if minimumCoverage > 0 {
                let count = (0..<(width * height)).reduce(0) { $0 + (green($1) ? 1 : 0) }
                guard Double(count) >= minimumCoverage * Double(width * height) else { return false }
            }
            for y in 1..<(height - 1) {
                for x in 1..<(width - 1) where green(y * width + x) {
                    let center = y * width + x
                    if [-width, 0, width].allSatisfy({ line in
                        [-1, 0, 1].allSatisfy { green(center + line + $0) }
                    }) { return true }
                }
            }
            return false
        }
    }
}
