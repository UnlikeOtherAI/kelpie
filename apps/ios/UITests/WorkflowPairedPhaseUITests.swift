import XCTest

extension WorkflowCaptureUITests {
    @MainActor
    func testPairedMCPWithBoundedPhaseObservation() async throws {
        let (fixture, tab) = try await ready()
        defer { fixture.listener.cancel() }
        let steps: [Body] = [
            ["action": "wait-ready", "selector": "button"],
            ["action": "click", "target": ["role": "button", "name": "Submit"]],
            ["action": "output", "name": "documentTitle", "source": "title"],
            ["action": "extract", "name": "tapGeometry", "params": ["fields": [["name": "center", "selector": "#geometry", "source": "text"]]]]
        ]
        let script: Body = ["version": 1, "tabId": tab, "actions": steps,
                            "capture": ["formats": ["gif", "video", "screenshots"], "fps": 8, "maxWidth": 384],
                            "tapIndicator": ["color": "#00FF00", "radius": 25, "durationMs": 2500],
                            "pointer": ["enabled": true, "curve": "s", "durationMs": 400]]
        let started = ProcessInfo.processInfo.systemUptime
        let playback = Task.detached { [probe] in
            do {
                let value = try await probe.toolEnvelope("kelpie_play_script", script)
                return (value as Body?, ProcessInfo.processInfo.systemUptime, "response")
            } catch {
                return (nil as Body?, ProcessInfo.processInfo.systemUptime, "request-error")
            }
        }
        let monitor = Task.detached { [probe] in
            await WorkflowPairedPhaseRecorder.observe(probe: probe, started: started)
        }
        let (response, responseTime, transport) = await playback.value
        monitor.cancel()
        let observation = await monitor.value
        let envelope = response ?? [:]
        let terminal: Body?
        if envelope["ok"] as? Bool == true {
            terminal = envelope["value"] as? Body
        } else {
            terminal = try? await probe.request("/v1/get-script-status", [:], timeout: 3)
        }
        let run = terminal?["runId"] as? String
        let matches = run != nil && observation.runID == run
        let error = terminal?["runError"] as? Body ?? terminal?["error"] as? Body ?? [:]
        let known = ["TIMEOUT", "INPUT_UNCERTAIN", "CAPTURE_VIEWPORT_CHANGED", "CAPTURE_VIEWPORT_UNSTABLE",
                     "SCRIPT_ABORTED", "AUTHORIZATION_REVOKED", "TAB_CHANGED", "WEBVIEW_ERROR"]
        let code = error["code"] as? String ?? "NONE"
        let count = terminal?["actionsExecuted"] as? Int
        let report = WorkflowPairedPhaseRecorder.Report(
            requestStartMs: 0,
            stopObserved: nil,
            stopObservedMs: nil,
            responseMs: Int((responseTime - started) * 1000),
            transport: transport,
            runMatched: matches,
            terminalCode: known.contains(code) ? code : (code == "NONE" ? "NONE" : "OTHER"),
            mayHaveCompleted: terminal?["mayHaveCompleted"] as? Bool,
            actionsExecuted: count.flatMap { (0...1_000_000).contains($0) ? $0 : nil },
            attempts: observation.attempts,
            observations: matches ? observation.samples : [],
            limitation: "bounded read-only polling may affect timing; native marker and Stop are tested separately"
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let attachment: XCTAttachment
        if let data = try? encoder.encode(report) {
            attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
        } else {
            attachment = XCTAttachment(string: "Phase report encoding failed")
        }
        attachment.name = "Paired run bounded phase observation"
        attachment.lifetime = .keepAlways
        add(attachment)
        guard response != nil else { XCTFail("Paired MCP request failed before a response"); return }
        guard envelope["ok"] as? Bool == true else { XCTFail("MCP play failed; terminal code: " + report.terminalCode); return }
        let result = try XCTUnwrap(envelope["value"] as? Body)
        XCTAssertEqual(result["success"] as? Bool, true)
        XCTAssertEqual((result["outputs"] as? Body)?["documentTitle"] as? String, "Count 1")
        let geometry = try XCTUnwrap((result["outputs"] as? Body)?["tapGeometry"] as? Body)
        let text = try XCTUnwrap(((geometry["fields"] as? [Body])?.first?["values"] as? [String])?.first)
        let actual = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(text.utf8)) as? Body)
        XCTAssertEqual(actual["centered"] as? Bool, true)
        let runID = try XCTUnwrap(result["runId"] as? String)
        let manifests = try XCTUnwrap(result["artifacts"] as? [Body])
        XCTAssertEqual(manifests.filter { $0["mimeType"] as? String == "image/png" }.count, steps.count)
        XCTAssertEqual(Set(manifests.compactMap { $0["mimeType"] as? String }), ["image/png", "image/gif", "video/mp4"])
        for manifest in manifests { try await inspect(manifest, run: runID) }
    }
}
