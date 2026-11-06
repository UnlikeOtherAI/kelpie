import AVFoundation
import ImageIO
import UIKit
import XCTest

final class WorkflowCaptureUITests: XCTestCase {
    typealias Body = [String: Any]
    let probe = WorkflowCaptureProbe(port: 28429)
    var cleanupProbe: WorkflowCaptureProbe?
    private let app = XCUIApplication()
    var testLaunchArguments: [String] = []

    @MainActor
    func ready() async throws -> (WorkflowLoopbackPage, String) {
        let fixture = try WorkflowLoopbackPage()
        let url = try await fixture.start()
        if testLaunchArguments.contains("--test-pinch-content-mode") {
            let port = try XCTUnwrap(fixture.listener.port?.rawValue)
            testLaunchArguments += ["--test-pinch-fixture-port", String(port)]
        }
        let tab = try await openOwnedTab(url: "about:blank")
        try await waitForBlankFixtureAdmission(tab: tab)
        let navigated = try await probe.request("/v1/play-script", ["version": 1, "tabId": tab,
                                                                   "actions": [["action": "navigate", "url": url]]])
        guard navigated["success"] as? Bool == true else {
            let code = (navigated["error"] as? Body)?["code"] as? String ?? "UNKNOWN"
            throw NSError(domain: "WorkflowFixtureNavigation", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Initial fixture navigation failed: " + code
            ])
        }
        return (fixture, tab)
    }

    @MainActor
    private func waitForBlankFixtureAdmission(tab: String) async throws {
        let deadline = ProcessInfo.processInfo.systemUptime + 10
        var stableSince: TimeInterval?
        var last: Body = [:]
        repeat {
            let listing = try await probe.request("/v1/get-tabs", [:])
            let selected = (listing["tabs"] as? [Body])?.first { $0["id"] as? String == tab }
            let active = listing["activeTab"] as? String == tab
            let loading = selected?["isLoading"] as? Bool
            let ready = try await probe.request("/v1/browser-control", [
                "version": 1, "tabId": tab, "method": "tab.ready", "params": ["state": "complete"]
            ])
            let status = try await probe.request("/v1/browser-control", [
                "version": 1, "tabId": tab, "method": "tab.status", "params": [:]
            ])
            let complete = ready["ok"] as? Bool == true && (ready["value"] as? Body)?["ready"] as? Bool == true
            let statusValue = status["value"] as? Body
            let observedURL = statusValue?["url"] as? String
            let statusOK = status["ok"] as? Bool == true
            let blank = statusOK && observedURL == "about:blank" && statusValue?["documentState"] as? String == "complete"
            last = ["active": active, "loadingKnown": loading != nil, "loading": loading ?? true,
                    "complete": complete, "statusOK": statusOK, "urlKnown": observedURL != nil, "blank": blank]
            let now = ProcessInfo.processInfo.systemUptime
            if active && loading == false && complete && blank {
                if let stableSince, now - stableSince >= 0.2 { return }
                if stableSince == nil { stableSince = now }
            } else {
                stableSince = nil
            }
            try await Task.sleep(nanoseconds: 100_000_000)
        } while ProcessInfo.processInfo.systemUptime < deadline
        let attachment = XCTAttachment(data: try JSONSerialization.data(withJSONObject: last, options: [.sortedKeys]),
                                       uniformTypeIdentifier: "public.json")
        attachment.name = "Blank fixture admission facts"
        attachment.lifetime = .keepAlways
        add(attachment)
        throw NSError(domain: "WorkflowFixtureAdmission", code: 1,
                      userInfo: [NSLocalizedDescriptionKey: "Blank tab did not reach stable read-only readiness"])
    }

    @MainActor
    func openOwnedTab(url: String) async throws -> String {
        continueAfterFailure = false
        app.launchArguments = ["--port", String(probe.port), "-hideWelcomeCard", "YES", "-homeURL", "about:blank"] + testLaunchArguments
        app.launch()
        XCTAssertTrue(app.buttons["browser.more"].waitForExistence(timeout: 20))
        try await probe.pair(app: app)
        let listing = try await probe.request("/v1/get-tabs", [:])
        let prior = try XCTUnwrap(listing["activeTab"] as? String)
        let created = try await probe.request("/v1/new-tab", ["url": url, "name": "Workflow UI test"])
        let tab = try XCTUnwrap(created["tabId"] as? String)
        addTeardownBlock { [self] in
            let client = cleanupProbe ?? probe
            let closed = try await client.request("/v1/close-tab", ["tabId": tab])
            XCTAssertEqual(closed["success"] as? Bool, true)
            if !prior.isEmpty { _ = try await client.request("/v1/switch-tab", ["tabId": prior]) }
            _ = try await client.request("/v1/pair", method: "DELETE")
        }
        return tab
    }

    @MainActor
    func testMarkerDetectorRecognizesFadedGreenWithoutAcceptingGray() throws {
        func image(_ color: UIColor, small: Bool = false) throws -> CGImage {
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            return try XCTUnwrap(UIGraphicsImageRenderer(size: CGSize(width: 20, height: 20), format: format).image { renderer in
                UIColor.white.setFill()
                renderer.fill(CGRect(x: 0, y: 0, width: 20, height: 20))
                color.setFill()
                renderer.fill(small ? CGRect(x: 9, y: 9, width: 1, height: 1) : CGRect(x: 0, y: 0, width: 20, height: 20))
            }.cgImage)
        }
        let faded = UIColor(red: 148.0 / 255, green: 241.0 / 255, blue: 149.0 / 255, alpha: 1)
        XCTAssertTrue(WorkflowCaptureProbe.containsMarker(try image(faded), minimumCoverage: 0.12))
        XCTAssertFalse(WorkflowCaptureProbe.containsMarker(try image(.lightGray), minimumCoverage: 0.12))
        XCTAssertFalse(WorkflowCaptureProbe.containsMarker(try image(faded, small: true), minimumCoverage: 0.12))
        func marker(offset: CGFloat) throws -> CGImage {
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            return try XCTUnwrap(UIGraphicsImageRenderer(size: CGSize(width: 100, height: 100), format: format).image { renderer in
                UIColor.white.setFill()
                renderer.fill(CGRect(x: 0, y: 0, width: 100, height: 100))
                faded.setFill()
                renderer.cgContext.fillEllipse(in: CGRect(x: 25, y: 25 + offset, width: 50, height: 50))
            }.cgImage)
        }
        let target = CGRect(x: 25, y: 25, width: 50, height: 50)
        let app = CGRect(x: 0, y: 0, width: 100, height: 100)
        XCTAssertTrue(WorkflowCaptureProbe.containsCenteredMarker(try marker(offset: 0), target: target, app: app))
        XCTAssertFalse(WorkflowCaptureProbe.containsCenteredMarker(try marker(offset: -20), target: target, app: app))
    }

    @MainActor
    func testInitialOwnedHTTPNavigationLoadsFixture() async throws {
        let (fixture, tab) = try await ready()
        defer { fixture.listener.cancel() }
        let httpCapabilities = try await probe.request("/v1/get-capabilities", [:])
        let mcpCapabilities = try await probe.call("kelpie_get_capabilities", [:])
        let httpWorkflow = try XCTUnwrap(httpCapabilities["scriptWorkflow"] as? Body)
        let mcpWorkflow = try XCTUnwrap(mcpCapabilities["scriptWorkflow"] as? Body)
        XCTAssertTrue((httpWorkflow as NSDictionary).isEqual(to: mcpWorkflow))
        XCTAssertEqual(httpWorkflow["supportedActions"] as? [String],
                       ["assert", "click", "commentary", "extract", "fill", "navigate", "output",
                        "screenshot", "scroll", "tap", "type", "wait", "wait-ready"])
        XCTAssertEqual(httpWorkflow["nativeSessions"] as? Bool, false)
        XCTAssertEqual(httpWorkflow["inputGuarantee"] as? String, "synthetic-coordinate")
        let formats = Set(try XCTUnwrap(httpWorkflow["captureFormats"] as? [String]))
        XCTAssertTrue(Set(["gif", "screenshots"]).isSubset(of: formats))
        XCTAssertTrue(formats.isSubset(of: Set(["gif", "screenshots", "video"])))
        XCTAssertEqual((httpWorkflow["webMcp"] as? Body)?["available"] as? Bool, false)
        XCTAssertEqual((httpWorkflow["lightpanda"] as? Body)?["available"] as? Bool, false)
        let result = try await probe.request("/v1/play-script", [
            "version": 1, "tabId": tab, "actions": [["action": "output", "name": "title", "source": "title"]]
        ])
        XCTAssertEqual(result["success"] as? Bool, true)
        XCTAssertEqual((result["outputs"] as? Body)?["title"] as? String, "Count 0")
        let evidence = XCTAttachment(screenshot: app.screenshot())
        evidence.name = "Owned tab after real HTTP workflow navigation"
        evidence.lifetime = .keepAlways
        add(evidence)
    }

    @MainActor
    func testPairedMCPClickShowsNativeMarkerAndDownloadsDecodedMedia() async throws {
        testLaunchArguments.append("--test-paired-geometry-receipt")
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
        let playback = Task.detached { [probe] in try await probe.toolEnvelope("kelpie_play_script", script) }
        let stop = app.buttons["browser.recording.stop"]
        XCTAssertTrue(stop.waitForExistence(timeout: 15))
        let deadline = Date().addingTimeInterval(10)
        var visible = false
        var pollCount = 0
        let pollStart = Date()
        var mismatch: (screen: XCUIScreenshot, target: CGRect, viewport: CGRect, greenElsewhere: Bool)?
        repeat {
            let viewport = app.webViews.firstMatch
            let submit = viewport.buttons["Submit"].firstMatch
            let viewportFrame = viewport.exists ? viewport.frame : .null
            let target = !viewportFrame.isNull && submit.exists ? submit.frame.intersection(viewportFrame) : .null
            let screen = app.screenshot()
            pollCount += 1
            if !target.isNull, WorkflowCaptureProbe.containsTargetMarker(screen, visibleTarget: target, app: app.frame) {
                let geometry = XCTAttachment(string: "Visible Submit frame in app screen points: " + String(describing: target))
                geometry.name = "Native marker target geometry"
                geometry.lifetime = .keepAlways
                add(geometry)
                let evidence = XCTAttachment(screenshot: screen)
                evidence.name = "Native workflow marker and Stop"
                evidence.lifetime = .keepAlways
                add(evidence)
                visible = true
                break
            }
            if mismatch == nil || stop.exists {
                let greenElsewhere = screen.image.cgImage.map { WorkflowCaptureProbe.containsMarker($0) } ?? false
                if mismatch == nil || (target.isNull == false && mismatch?.target.isNull == true) ||
                    (greenElsewhere && mismatch?.greenElsewhere == false) {
                    mismatch = (screen, target, viewportFrame, greenElsewhere)
                }
            }
            try await Task.sleep(nanoseconds: 70_000_000)
        } while Date() < deadline && stop.exists
        if !visible, let mismatch {
            let screenshot = XCTAttachment(screenshot: mismatch.screen)
            screenshot.name = "Native marker check failed while Stop was visible"
            screenshot.lifetime = .keepAlways
            add(screenshot)
            let geometry = XCTAttachment(string: "Visible Submit frame " + String(describing: mismatch.target) +
                ", WebView frame " + String(describing: mismatch.viewport) +
                ", app frame " + String(describing: app.frame) +
                ", green component elsewhere " + String(mismatch.greenElsewhere) +
                ", polls " + String(pollCount) + ", elapsed " + String(Date().timeIntervalSince(pollStart)) +
                ", Stop visible " + String(stop.exists))
            geometry.name = "Failed marker target geometry"
            geometry.lifetime = .keepAlways
            add(geometry)
        }
        let envelope = try await playback.value
        if envelope["ok"] as? Bool != true {
            // The click may have completed before later capture failed. Read the
            // synthetic fixture's geometry without repeating or mutating input.
            await attachFixtureGeometry(tab: tab)
            let status = try await probe.call("kelpie_get_script_status", [:])
            let error = status["runError"] as? Body ?? [:]
            try await attachImmersiveLayoutTrace(runID: XCTUnwrap(status["runId"] as? String))
            if ["CAPTURE_VIEWPORT_CHANGED", "CAPTURE_VIEWPORT_UNSTABLE"].contains(WorkflowCaptureProbe.errorCode(["error": error])) {
                let diagnostic = try await probe.request("/v1/debug-screens", [:])
                let receipt = try XCTUnwrap(diagnostic["testCaptureEvidence"] as? Body)
                XCTAssertEqual(try XCTUnwrap(receipt["runId"] as? String), try XCTUnwrap(status["runId"] as? String))
                let snapshot = receipt["viewportRefusal"] as? Body ?? ["site": "unavailable"]
                let data = try JSONSerialization.data(withJSONObject: snapshot, options: [.sortedKeys])
                let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
                attachment.name = "Paired run exact viewport refusal"
                attachment.lifetime = .keepAlways
                add(attachment)
            }
            XCTFail("MCP play failed; terminal code: " + WorkflowCaptureProbe.errorCode(["error": error]))
            return
        }
        let result = try XCTUnwrap(envelope["value"] as? Body)
        try await attachImmersiveLayoutTrace(runID: XCTUnwrap(result["runId"] as? String))
        XCTAssertEqual(result["success"] as? Bool, true, "\(result["error"] ?? "")")
        XCTAssertEqual((result["outputs"] as? Body)?["documentTitle"] as? String, "Count 1")
        let geometry = try XCTUnwrap((result["outputs"] as? Body)?["tapGeometry"] as? Body)
        let text = try XCTUnwrap(((geometry["fields"] as? [Body])?.first?["values"] as? [String])?.first)
        let data = Data(text.utf8)
        let actual = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? Body)
        let evidence = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
        evidence.name = "Fixture click and visual viewport geometry"
        evidence.lifetime = .keepAlways
        add(evidence)
        XCTAssertEqual(actual["centered"] as? Bool, true)
        let run = try XCTUnwrap(result["runId"] as? String)
        let manifests = try XCTUnwrap(result["artifacts"] as? [Body])
        XCTAssertEqual(manifests.filter { $0["mimeType"] as? String == "image/png" }.count, steps.count)
        XCTAssertEqual(Set(manifests.compactMap { $0["mimeType"] as? String }), ["image/png", "image/gif", "video/mp4"])
        for manifest in manifests { try await inspect(manifest, run: run) }
        XCTAssertTrue(visible, "Expected a connected green marker at the visible Submit button center")
    }

    @MainActor
    private func attachImmersiveLayoutTrace(runID: String) async throws {
        let diagnostic = try await probe.request("/v1/debug-screens", [:])
        let receipt = try XCTUnwrap(diagnostic["testImmersiveLayout"] as? Body)
        XCTAssertEqual(try XCTUnwrap(receipt["runId"] as? String), runID)
        let attachment = XCTAttachment(data: try JSONSerialization.data(withJSONObject: receipt, options: [.sortedKeys]),
                                       uniformTypeIdentifier: "public.json")
        attachment.name = "Paired run immersive layout receipt"
        attachment.lifetime = .keepAlways
        add(attachment)
        XCTAssertEqual(receipt["identityValid"] as? Bool, true)
        XCTAssertNotNil(receipt["request"])
        XCTAssertNotNil(receipt["application"])
        XCTAssertNotNil(receipt["baseline"])
    }

    @MainActor
    private func attachFixtureGeometry(tab: String) async {
        let response = try? await probe.request("/v1/browser-control", [
            "version": 1, "tabId": tab, "method": "tab.extract",
            "params": ["fields": [["name": "geometry", "selector": "#geometry", "source": "text"]]]
        ])
        guard let value = response?["value"] as? Body,
              let fields = value["fields"] as? [Body],
              let text = (fields.first?["values"] as? [String])?.first,
              let data = text.data(using: .utf8),
              (try? JSONSerialization.jsonObject(with: data)) is Body else { return }
        let evidence = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
        evidence.name = "Fixture click geometry after failed capture"
        evidence.lifetime = .keepAlways
        add(evidence)
    }

    @MainActor
    private func inspect(_ manifest: Body, run: String) async throws {
        let bytes = try await probe.bytes(manifest, run: run)
        let type = try XCTUnwrap(manifest["mimeType"] as? String)
        let width = try XCTUnwrap(manifest["width"] as? Int)
        XCTAssertEqual(manifest["partial"] as? Bool, false)
        if type == "video/mp4" {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mp4")
            try bytes.write(to: url)
            defer { try? FileManager.default.removeItem(at: url) }
            let asset = AVURLAsset(url: url)
            let duration = try await asset.load(.duration)
            XCTAssertGreaterThan(duration.seconds, 1)
            let generator = AVAssetImageGenerator(asset: asset)
            generator.requestedTimeToleranceBefore = .zero
            generator.requestedTimeToleranceAfter = CMTime(value: 1, timescale: 4)
            var marker = false
            for second in stride(from: 0.0, to: duration.seconds, by: 0.25) {
                let frame = try await generator.image(at: CMTime(seconds: second, preferredTimescale: 600)).image
                XCTAssertEqual(frame.width, width)
                marker = marker || WorkflowCaptureProbe.containsMarker(frame)
                if marker { break }
            }
            XCTAssertTrue(marker)
        } else {
            let source = try XCTUnwrap(CGImageSourceCreateWithData(bytes as CFData, nil))
            let count = CGImageSourceGetCount(source)
            var marker = false
            for index in 0..<count {
                let frame = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, index, nil))
                XCTAssertEqual(frame.width, width)
                marker = marker || WorkflowCaptureProbe.containsMarker(frame)
            }
            if type == "image/gif" || manifest["actionIndex"] as? Int == 1 { XCTAssertTrue(marker) }
            if type == "image/gif" {
                XCTAssertGreaterThan(count, 3)
                let props = try XCTUnwrap(CGImageSourceCopyProperties(source, nil) as? [String: Any])
                let gif = try XCTUnwrap(props[kCGImagePropertyGIFDictionary as String] as? [String: Any])
                XCTAssertEqual(gif[kCGImagePropertyGIFLoopCount as String] as? Int, 0)
            }
        }
        let attachment = XCTAttachment(data: bytes, uniformTypeIdentifier: type == "image/gif" ? "com.compuserve.gif" :
            type == "video/mp4" ? "public.mpeg-4" : "public.png")
        attachment.name = type.replacingOccurrences(of: "/", with: "-") + "-" + String(manifest["actionIndex"] as? Int ?? 0)
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    func testFullPreflightForeignOwnerAndNativeStopRecoverWithoutInputReplay() async throws {
        let (fixture, tab) = try await ready()
        defer { fixture.listener.cancel() }
        let tap: Body = ["action": "tap", "target": ["role": "button", "name": "Submit"]]
        let rejected = try await probe.request("/v1/play-script", ["version": 1, "tabId": tab, "actions": [tap, ["action": "press-key", "key": "Enter"]]])
        XCTAssertEqual((rejected["error"] as? Body)?["code"] as? String, "UNSUPPORTED_SCRIPT_ACTION")
        let other = WorkflowCaptureProbe(port: probe.port)
        try await other.pair(app: app)
        addTeardownBlock { _ = try await other.request("/v1/pair", method: "DELETE") }
        let ongoing = Task.detached { [probe] in
            try await probe.request("/v1/play-script", ["version": 1, "tabId": tab, "actions": [["action": "wait", "ms": 20000], tap]])
        }
        let stop = app.buttons["browser.recording.stop"]
        XCTAssertTrue(stop.waitForExistence(timeout: 8))
        let status = try await probe.request("/v1/get-script-status", [:])
        let run = try XCTUnwrap(status["runId"] as? String)
        let foreign = try await other.request("/v1/abort-script", ["runId": run])
        XCTAssertEqual((foreign["error"] as? Body)?["code"] as? String, "RUN_NOT_FOUND")
        stop.tap()
        let aborted = try await ongoing.value
        XCTAssertEqual((aborted["error"] as? Body)?["code"] as? String, "SCRIPT_ABORTED")
        let recovery = try await probe.call("kelpie_get_script_status", ["runId": run])
        XCTAssertEqual(recovery["success"] as? Bool, true)
        XCTAssertEqual(recovery["state"] as? String, "aborted")
        XCTAssertEqual(recovery["runSuccess"] as? Bool, false)
        XCTAssertEqual((recovery["runError"] as? Body)?["code"] as? String, "SCRIPT_ABORTED")
        XCTAssertNil(recovery["error"])
        XCTAssertNil(recovery["outputs"])
        let verified = try await probe.request("/v1/play-script", ["version": 1, "tabId": tab,
            "actions": [["action": "output", "name": "documentTitle", "source": "title"]]])
        XCTAssertEqual((verified["outputs"] as? Body)?["documentTitle"] as? String, "Count 0")
    }
}
