import XCTest

extension WorkflowCaptureUITests {
    @MainActor
    func testInferredPasswordCaptureRefusalRedactsEarlierNamedOutputsAndDiscardsFrames() async throws {
        try await sensitiveRefusal(path: "/secret-guard", selector: "input[type=password]", throughMCP: false, focused: false)
    }

    @MainActor
    func testFocusPasswordRefusalRedactsEarlierOutputsAndDiscardsFrames() async throws {
        try await sensitiveRefusal(path: "/focus-secret-password", selector: "#entry", throughMCP: false, focused: true)
    }

    @MainActor
    func testFocusAutocompleteRefusalThroughMCPRedactsEarlierOutputsAndDiscardsFrames() async throws {
        try await sensitiveRefusal(path: "/focus-secret-autocomplete", selector: "#entry", throughMCP: true, focused: true)
    }

    @MainActor
    private func sensitiveRefusal(path: String, selector: String, throughMCP: Bool, focused: Bool) async throws {
        let (fixture, tab) = try await ready()
        defer { fixture.listener.cancel() }
        let origin = "http://127.0.0.1:" + String(try XCTUnwrap(fixture.listener.port?.rawValue))
        let canary = "iOS Reflected+Canary!"
        let variants = [canary, "iOS%20Reflected%2bCanary!", "iOS+Reflected%2bCanary%21"]
        let workflow: Body = [
            "version": 1, "tabId": tab, "capture": ["formats": ["screenshots"]],
            "actions": [
                ["action": "navigate", "url": origin + path],
                ["action": "output", "source": "title", "name": "before"],
                ["action": "fill", "target": ["selector": selector], "text": canary]
            ]
        ]
        if throughMCP {
            let envelope = try await probe.toolEnvelope("kelpie_extension", ["name": "kelpie_play_script", "arguments": workflow])
            XCTAssertEqual(envelope["ok"] as? Bool, false)
            XCTAssertEqual((envelope["error"] as? Body)?["code"] as? String, "COMMAND_FAILED")
            let metadata = try await probe.call("kelpie_get_script_status", [:])
            XCTAssertEqual(metadata["runSuccess"] as? Bool, false)
            XCTAssertEqual((metadata["runError"] as? Body)?["code"] as? String, "SENSITIVE_CAPTURE_REFUSED")
            XCTAssertTrue((metadata["artifacts"] as? [Body])?.isEmpty == true)
            XCTAssertNil(metadata["outputs"])
            let exposed = String(decoding: try JSONSerialization.data(withJSONObject: [envelope, metadata]), as: UTF8.self)
            XCTAssertTrue(variants.allSatisfy { !exposed.contains($0) })
        }
        let failed = try await probe.request("/v1/play-script", workflow)
        XCTAssertEqual((failed["error"] as? Body)?["code"] as? String, "SENSITIVE_CAPTURE_REFUSED")
        XCTAssertEqual(failed["actionsExecuted"] as? Int, 2)
        if focused { XCTAssertEqual(failed["mayHaveCompleted"] as? Bool, true) }
        XCTAssertTrue((failed["artifacts"] as? [Body])?.isEmpty == true)
        let scrubbed = try XCTUnwrap((failed["outputs"] as? Body)?["before"] as? String)
        XCTAssertTrue(variants.allSatisfy { !scrubbed.contains($0) })
        XCTAssertFalse(String(decoding: try JSONSerialization.data(withJSONObject: failed), as: UTF8.self).contains(canary))
        let status = try await probe.call("kelpie_get_script_status", ["runId": try XCTUnwrap(failed["runId"] as? String)])
        XCTAssertNil(status["outputs"])
        XCTAssertTrue((status["artifacts"] as? [Body])?.isEmpty == true)
        XCTAssertFalse(String(decoding: try JSONSerialization.data(withJSONObject: status), as: UTF8.self).contains(canary))
        let untouched = try await probe.request("/v1/play-script", [
            "version": 1, "tabId": tab, "actions": [["action": "output", "name": "page", "source": "title"]]
        ])
        XCTAssertEqual((untouched["outputs"] as? Body)?["page"] as? String, variants.joined(separator: " | "))
    }

    @MainActor
    func testWorkflowTapExpiresPriorBrowserReferenceWithoutReplayingIt() async throws {
        let (fixture, tab) = try await ready()
        defer { fixture.listener.cancel() }
        func control(_ method: String, _ params: Body) async throws -> Body {
            try await probe.request("/v1/browser-control", ["version": 1, "method": method, "tabId": tab, "params": params])
        }
        func buttonRef() async throws -> String {
            let response = try await control("tab.snapshot", ["maxElements": 100])
            let elements = try XCTUnwrap((response["value"] as? Body)?["elements"] as? [Body])
            return try XCTUnwrap(elements.first { $0["name"] as? String == "Submit" }?["ref"] as? String)
        }
        let stale = try await buttonRef()
        let result = try await probe.call("kelpie_play_script", [
            "version": 1, "tabId": tab, "actions": [["action": "tap", "target": ["role": "button", "name": "Submit"]]]
        ])
        XCTAssertEqual(result["success"] as? Bool, true)
        let refused = try await control("tab.click", ["ref": stale])
        XCTAssertEqual((refused["error"] as? Body)?["code"] as? String, "STALE_REFERENCE")
        XCTAssertEqual((refused["error"] as? Body)?["mayHaveCompleted"] as? Bool, false)
        let fresh = try await buttonRef()
        let accepted = try await control("tab.click", ["ref": fresh])
        XCTAssertEqual(accepted["ok"] as? Bool, true)
        let verified = try await probe.request("/v1/play-script", [
            "version": 1, "tabId": tab, "actions": [["action": "output", "source": "title", "name": "count"]]
        ])
        XCTAssertEqual((verified["outputs"] as? Body)?["count"] as? String, "Count 2")
    }

    @MainActor
    func testDiscoveredNamedControlsCancelAnOwnedHTTPPlay() async throws {
        let (fixture, tab) = try await ready()
        defer { fixture.listener.cancel() }
        let required = ["kelpie_play_script", "kelpie_abort_script", "kelpie_get_script_status", "kelpie_get_script_artifact"]
        let names = try await probe.toolValue("kelpie_extensions", [:])
        XCTAssertTrue(Set(required).isSubset(of: Set(try XCTUnwrap(names as? [String]))))
        let schemas = try await probe.toolValue("kelpie_extension_tools", ["names": required])
        let expanded = try XCTUnwrap(schemas as? [Body])
        XCTAssertEqual(Set(expanded.compactMap { $0["name"] as? String }), Set(required))
        XCTAssertTrue(expanded.allSatisfy { $0["inputSchema"] is Body })

        let task = Task.detached { [probe] in
            try await probe.request("/v1/play-script", ["version": 1, "tabId": tab, "actions": [["action": "wait", "ms": 10000]]])
        }
        let stop = XCUIApplication().buttons["browser.recording.stop"]
        XCTAssertTrue(stop.waitForExistence(timeout: 6))
        let status = try await probe.toolValue("kelpie_get_script_status", [:])
        let run = try XCTUnwrap((status as? Body)?["runId"] as? String)
        let abort = try await probe.toolValue("kelpie_abort_script", ["runId": run])
        XCTAssertEqual((abort as? Body)?["abortRequested"] as? Bool, true)
        let result = try await task.value
        XCTAssertEqual(result["state"] as? String, "aborted")
        let recovered = try await probe.call("kelpie_get_script_status", ["runId": run])
        XCTAssertEqual(recovered["runSuccess"] as? Bool, false)
        XCTAssertNil(recovered["outputs"])
    }

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
                ["action": "wait", "ms": 15000], ["action": "click", "target": ["role": "button", "name": "Submit"]]
            ]])
        }
        let stop = XCUIApplication().buttons["browser.recording.stop"]
        XCTAssertTrue(stop.waitForExistence(timeout: 8))
        let active = try await probe.call("kelpie_get_script_status", [:])
        XCTAssertTrue((active["artifacts"] as? [Body])?.isEmpty == true)
        let activeID = try XCTUnwrap(active["runId"] as? String)
        let premature = range.merging(["runId": activeID]) { _, new in new }
        let notReady = try await probe.request("/v1/get-script-artifact", premature)
        XCTAssertEqual((notReady["error"] as? Body)?["code"] as? String, "ARTIFACT_NOT_READY")
        let malformed = try await probe.request("/v1/get-script-artifact", premature.merging(["length": true]) { _, new in new })
        XCTAssertEqual((malformed["error"] as? Body)?["code"] as? String, "INVALID_PARAM")
        let hidden = try await second.request("/v1/get-script-artifact", premature)
        XCTAssertEqual((hidden["error"] as? Body)?["code"] as? String, "ARTIFACT_NOT_FOUND")
        let older = try await probe.request("/v1/get-script-artifact", range)
        XCTAssertEqual(older["nextOffset"] as? Int, 1)
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
        XCTAssertEqual(run["success"] as? Bool, true, "Workflow error: " + WorkflowCaptureProbe.errorCode(run))
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
