import XCTest

extension WorkflowCaptureUITests {
    @MainActor
    func testColdPriorHTTPEitherNavigatesOrRefusesBeforeLoadThenRecovers() async throws {
        let fixture = try WorkflowLoopbackPage(responseDelay: 0.4)
        let origin = try await fixture.start().replacingOccurrences(of: "/workflow", with: "")
        defer { fixture.listener.cancel() }
        var report: Body = ["phase": "pairing"]
        defer {
            if let data = try? JSONSerialization.data(withJSONObject: report, options: [.sortedKeys]) {
                let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
                attachment.name = "Cold HTTP navigation admission and API recovery"
                attachment.lifetime = .keepAlways
                add(attachment)
            }
        }
        do {
            let tab = try await openOwnedTab(url: origin + "/cold-prior")
            report["phase"] = "initial-navigation"
            let initial = try await probe.request("/v1/play-script", [
                "version": 1, "tabId": tab, "actions": [["action": "navigate", "url": origin + "/cold-destination"]]
            ])
            let succeeded = initial["success"] as? Bool == true
            report["initialSuccess"] = succeeded
            report["initialCode"] = (initial["error"] as? Body)?["code"] ?? "none"
            report["actionsExecuted"] = initial["actionsExecuted"] ?? 0
            report["mayHaveCompleted"] = initial["mayHaveCompleted"] ?? false
            if !succeeded {
                XCTAssertEqual((initial["error"] as? Body)?["code"] as? String, "NAVIGATION_BUSY")
                XCTAssertNotEqual(initial["mayHaveCompleted"] as? Bool, true)
                XCTAssertEqual(initial["actionsExecuted"] as? Int, 0)
                XCTAssertEqual(fixture.requestCount(path: "/cold-destination"), 0)
            }
            report["phase"] = "natural-completion"
            let settled = try await probe.request("/v1/play-script", [
                "version": 1, "tabId": tab, "actions": [
                    ["action": "wait-ready", "state": "complete", "selector": "button", "timeoutMs": 20000],
                    ["action": "output", "source": "url", "name": "url"]
                ]
            ])
            XCTAssertEqual(settled["success"] as? Bool, true)
            XCTAssertEqual((settled["outputs"] as? Body)?["url"] as? String,
                           origin + (succeeded ? "/cold-destination" : "/cold-prior"))
            if !succeeded {
                XCTAssertEqual(fixture.requestCount(path: "/cold-destination"), 0)
                report["phase"] = "new-api-navigation"
                let recovered = try await probe.request("/v1/play-script", [
                    "version": 1, "tabId": tab, "actions": [
                        ["action": "navigate", "url": origin + "/cold-destination"],
                        ["action": "output", "source": "url", "name": "url"]
                    ]
                ])
                XCTAssertEqual(recovered["success"] as? Bool, true)
                XCTAssertEqual((recovered["outputs"] as? Body)?["url"] as? String, origin + "/cold-destination")
            }
            XCTAssertEqual(fixture.requestCount(path: "/cold-destination"), 1)
            report["destinationRequests"] = fixture.requestCount(path: "/cold-destination")
            report["phase"] = "completed"
        } catch {
            report["failureType"] = String(reflecting: type(of: error))
            throw error
        }
    }
}
