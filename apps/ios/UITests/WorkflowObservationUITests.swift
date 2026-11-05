import XCTest

extension WorkflowCaptureUITests {
    @MainActor
    func testRevocationStopsLaterInputAndDeniesSubsequentArtifactChunks() async throws {
        let (fixture, tab) = try await ready()
        defer { fixture.listener.cancel() }
        let second = WorkflowCaptureProbe(port: probe.port)
        try await second.pair(app: XCUIApplication())
        cleanupProbe = second
        let captured = try await probe.request("/v1/play-script", [
            "version": 1, "tabId": tab, "actions": [["action": "screenshot"]]
        ])
        let id = try XCTUnwrap(captured["runId"] as? String)
        let artifact = try XCTUnwrap((captured["artifacts"] as? [Body])?.first?["id"] as? String)
        let range: Body = ["runId": id, "artifactId": artifact, "offset": 0, "length": 1]
        let first = try await probe.request("/v1/get-script-artifact", range)
        XCTAssertEqual(first["nextOffset"] as? Int, 1)
        let foreign = try await second.request("/v1/get-script-artifact", range)
        XCTAssertEqual((foreign["error"] as? Body)?["code"] as? String, "ARTIFACT_NOT_FOUND")
        let running = Task.detached { [probe] in
            try await probe.request("/v1/play-script", ["version": 1, "tabId": tab, "actions": [
                ["action": "wait", "ms": 5000], ["action": "click", "target": ["role": "button", "name": "Submit"]]
            ]])
        }
        let stop = XCUIApplication().buttons["browser.recording.stop"]
        XCTAssertTrue(stop.waitForExistence(timeout: 8))
        _ = try await probe.request("/v1/pair", method: "DELETE")
        let denied = try await probe.request("/v1/get-script-artifact", range.merging(["offset": 1]) { _, new in new })
        XCTAssertEqual((denied["error"] as? Body)?["code"] as? String, "UNAUTHORIZED")
        let interrupted = try await running.value
        XCTAssertEqual((interrupted["error"] as? Body)?["code"] as? String, "UNAUTHORIZED")
        let next = try await second.request("/v1/play-script", [
            "version": 1, "tabId": tab, "actions": [["action": "output", "name": "title", "source": "title"]]
        ])
        XCTAssertEqual((next["outputs"] as? Body)?["title"] as? String, "Count 0")
    }

    /// Reads and extraction travel through the same paired app gateway used by authored workflows.
    @MainActor
    func testPrivateObservationTypedExtractionAndSensitiveTargetRecovery() async throws {
        let (fixture, tab) = try await ready()
        defer { fixture.listener.cancel() }
        func browser(_ method: String, _ params: Body) async throws -> Body {
            let reply = try await probe.request("/v1/browser-control", ["version": 1, "method": method, "tabId": tab, "params": params])
            XCTAssertEqual(reply["ok"] as? Bool, true, "\(reply["error"] ?? "")")
            return try XCTUnwrap(reply["value"] as? Body)
        }

        let snapshot = try await browser("tab.snapshot", ["scope": "main", "maxChars": 1024, "maxElements": 5])
        let observed = String(decoding: try JSONSerialization.data(withJSONObject: snapshot), as: UTF8.self)
        XCTAssertTrue(observed.contains("Alpha"))
        XCTAssertFalse(observed.contains("PRIVATE_"))
        XCTAssertFalse(observed.contains("Submit"))
        let status = try await browser("tab.status", [:])
        XCTAssertEqual((status["network"] as? Body)?["availability"] as? String, "unavailable")
        XCTAssertEqual((status["errors"] as? Body)?["availability"] as? String, "unavailable")
        let port = try XCTUnwrap(fixture.listener.port?.rawValue)
        let refusal = try await probe.request("/v1/browser-control", [
            "version": 1, "method": "tab.webmcp.discover", "tabId": tab, "params": ["origin": "http://127.0.0.1:\(port)"]
        ])
        XCTAssertEqual(refusal["ok"] as? Bool, false)
        XCTAssertNil(refusal["value"])
        let missing = try await browser("tab.ready", ["state": "complete", "selector": ".absent"])
        XCTAssertEqual(missing["ready"] as? Bool, false)
        let titles: Body = ["name": "rows", "selector": "article", "multiple": true, "source": "text",
                            "fields": [["name": "title", "selector": "h2", "source": "text"]]]
        let params: Body = ["scope": "main", "fields": [titles], "metadata": true]
        let direct = try await browser("tab.extract", params)
        let steps: [Body] = [["action": "assert", "state": "visible", "target": ["role": "button", "name": "Submit"]],
                             ["action": "wait-ready", "state": "complete", "selector": "button"],
                             ["action": "extract", "name": "products", "params": params]]
        let run = try await probe.request("/v1/play-script", ["version": 1, "tabId": tab, "actions": steps])
        XCTAssertEqual(run["success"] as? Bool, true)
        let products = try XCTUnwrap((run["outputs"] as? Body)?["products"] as? Body)
        XCTAssertTrue((products as NSDictionary).isEqual(to: direct))
        let rows = try XCTUnwrap((products["fields"] as? [Body])?.first?["records"] as? [[Body]])
        XCTAssertEqual(rows.compactMap { ($0.first?["values"] as? [String])?.first }, ["Alpha", "Beta"])
        let extracted = String(decoding: try JSONSerialization.data(withJSONObject: products), as: UTF8.self)
        XCTAssertFalse(extracted.contains("PRIVATE_"))
        XCTAssertTrue(extracted.contains("Public headline"))
        XCTAssertTrue(extracted.contains("provenance"))

        let fill: Body = ["action": "fill", "target": ["selector": "input[type=password]"], "text": "synthetic-secret"]
        let protected = try await probe.request("/v1/play-script", ["version": 1, "tabId": tab, "actions": [fill], "capture": ["formats": ["screenshots"]]])
        XCTAssertEqual((protected["error"] as? Body)?["code"] as? String, "SENSITIVE_CAPTURE_REFUSED")
        XCTAssertEqual((protected["artifacts"] as? [Body])?.count, 0)
        let resumed = try await probe.request("/v1/play-script", ["version": 1, "tabId": tab, "actions": [["action": "wait", "ms": 1]]])
        XCTAssertEqual(resumed["success"] as? Bool, true)
    }
}
