import AVFoundation
import CryptoKit
import ImageIO
import Network
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

    func toolValue(_ name: String, _ arguments: Body) async throws -> Any {
        let response = try await request("/mcp", ["jsonrpc": "2.0", "id": 1, "method": "tools/call", "params": [
            "name": name, "arguments": arguments
        ]])
        let result = try XCTUnwrap(response["result"] as? Body)
        let text = try XCTUnwrap((result["content"] as? [Body])?.first(where: { $0["type"] as? String == "text" })?["text"] as? String)
        let envelope = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(text.utf8)) as? Body)
        XCTAssertEqual(envelope["ok"] as? Bool, true, "\(envelope["error"] ?? "")")
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

    enum ProbeError: Error { case invalidChunk, pairing, listener }

    static func containsMarker(_ image: CGImage) -> Bool {
        let width = 200
        let height = max(1, width * image.height / image.width)
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        return pixels.withUnsafeMutableBytes { raw in
            guard let ctx = CGContext(data: raw.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return false }
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            for index in stride(from: 0, to: raw.count, by: 4) {
                if raw[index + 1] > 155, raw[index] < 90, raw[index + 2] < 95 { return true }
            }
            return false
        }
    }
}

/// The fixture is served by the test runner and stays on the simulator loopback interface.
final class WorkflowLoopbackPage {
    let listener: NWListener
    init() throws {
        let params = NWParameters.tcp
        params.requiredInterfaceType = .loopback
        listener = try NWListener(using: params, on: .any)
    }

    func start() async throws -> String {
        let queue = DispatchQueue(label: "kelpie.ios.workflow.fixture")
        let html = """
        <!doctype html><meta name="viewport" content="width=device-width,initial-scale=1"><title>Count 0</title>
        <style>body{background:white;color:black}button{display:block;margin:25vh auto;width:150px;height:80px}</style>
        <meta property="og:site_name" content="Fixture Press">
        <script type="application/ld+json">{"@type":"Article","headline":"Public headline","password":"PRIVATE_LD"}</script>
        <a id="continue" href="/landed">Continue</a><main><article><h2>Alpha</h2><a href="/alpha">Read</a></article><article><h2>Beta</h2></article>
        <input type="password" aria-label="Private input" value="PRIVATE_INPUT" oninput="document.title=this.value">
        <label>Entry <input id="entry" oninput="document.querySelector('#length').textContent=this.value.length"></label><output id="length"></output>
        <div contenteditable>PRIVATE_EDITOR</div></main>
        <button>Submit</button><output id="geometry"></output><script>
        window.count=0;document.querySelector('button').onclick=e=>{
          const r=e.currentTarget.getBoundingClientRect(),x=(Math.max(0,r.left)+Math.min(innerWidth,r.right))/2;
          const y=(Math.max(0,r.top)+Math.min(innerHeight,r.bottom))/2;
          document.querySelector('#geometry').textContent=Math.abs(x-e.clientX)<=1&&Math.abs(y-e.clientY)<=1?'center':'missed';
          document.title='Count '+(++window.count)
        }
        const button=document.querySelector('button');
        if(location.pathname==='/scroll'){
          document.documentElement.style.background='#D0D0D0';document.body.style='margin:0;background:#D0D0D0;height:300vh;position:relative';
          document.body.innerHTML='<button id="bottom" style="position:absolute;bottom:12px;left:12px;margin:0">Bottom</button>'
        }
        if(location.pathname==='/motion'){
          document.documentElement.style.background='#606060';document.body.style='margin:0;background:#606060';
          document.body.innerHTML='<button style="appearance:none;position:fixed;left:58vw;top:60vh;transform:translate(-50%,-50%);margin:0;background:#505050;color:#181818;border:0">Track</button>'
          document.querySelector('button').onclick=()=>{document.title='Track clicked'}
        }
        if(location.pathname==='/landed'){
          document.body.style.background='#1848D8';document.body.innerHTML='<h1 id="landed">Landed</h1>';document.title='Landed'
        }
        if(location.pathname==='/duplicates'){
          const copy=button.cloneNode(true);copy.style='position:fixed;left:8px;top:8px;margin:0';document.body.append(copy)
        }
        if(location.pathname==='/covered'){
          const cover=document.createElement('div');cover.style='position:fixed;inset:0;z-index:2';document.body.append(cover)
        }
        if(location.pathname==='/replace'){
          button.onpointerdown=()=>{document.title='Pointerdown 1';button.replaceWith(button.cloneNode(true))}
        }
        </script>
        """
        let data = Data("HTTP/1.1 200 OK\r\nContent-Type: text/html\r\nContent-Length: \(html.utf8.count)\r\nConnection: close\r\n\r\n\(html)".utf8)
        listener.newConnectionHandler = { connection in
            connection.start(queue: queue)
            connection.receive(minimumIncompleteLength: 1, maximumLength: 16384) { _, _, _, _ in
                connection.send(content: data, completion: .contentProcessed { _ in connection.cancel() })
            }
        }
        let port: UInt16 = try await withCheckedThrowingContinuation { continuation in
            listener.stateUpdateHandler = { [listener] state in
                switch state {
                case .ready:
                    listener.stateUpdateHandler = nil
                    if let port = listener.port { continuation.resume(returning: port.rawValue) }
                    else { continuation.resume(throwing: WorkflowCaptureProbe.ProbeError.listener) }
                case .failed(let error):
                    listener.stateUpdateHandler = nil
                    continuation.resume(throwing: error)
                default: break
                }
            }
            listener.start(queue: queue)
        }
        return "http://127.0.0.1:\(port)/workflow"
    }
    deinit { listener.cancel() }
}
