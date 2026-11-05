import AVFoundation
import ImageIO
import XCTest

final class WorkflowCaptureUITests: XCTestCase {
    typealias Body = [String: Any]
    let probe = WorkflowCaptureProbe(port: 28429)
    var cleanupProbe: WorkflowCaptureProbe?
    private let app = XCUIApplication()

    @MainActor
    func ready() async throws -> (WorkflowLoopbackPage, String) {
        continueAfterFailure = false
        app.launchArguments = ["--port", String(probe.port), "-hideWelcomeCard", "YES", "-homeURL", "about:blank"]
        app.launch()
        XCTAssertTrue(app.buttons["browser.more"].waitForExistence(timeout: 20))
        try await probe.pair(app: app)
        let fixture = try WorkflowLoopbackPage()
        let url = try await fixture.start()
        let listing = try await probe.request("/v1/get-tabs", [:])
        let prior = try XCTUnwrap(listing["activeTab"] as? String)
        let created = try await probe.request("/v1/new-tab", ["url": "about:blank", "name": "Workflow UI test"])
        let tab = try XCTUnwrap(created["tabId"] as? String)
        addTeardownBlock { [self] in
            let client = cleanupProbe ?? probe
            let closed = try await client.request("/v1/close-tab", ["tabId": tab])
            XCTAssertEqual(closed["success"] as? Bool, true)
            if !prior.isEmpty { _ = try await client.request("/v1/switch-tab", ["tabId": prior]) }
            _ = try await client.request("/v1/pair", method: "DELETE")
        }
        let navigated = try await probe.request("/v1/play-script", ["version": 1, "tabId": tab,
                                                                   "actions": [["action": "navigate", "url": url]]])
        XCTAssertEqual(navigated["success"] as? Bool, true, "\(navigated["error"] ?? "")")
        return (fixture, tab)
    }

    @MainActor
    func testPairedMCPClickShowsNativeMarkerAndDownloadsDecodedMedia() async throws {
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
        let playback = Task.detached { [probe] in try await probe.call("kelpie_play_script", script) }
        let stop = app.buttons["browser.recording.stop"]
        XCTAssertTrue(stop.waitForExistence(timeout: 15))
        let deadline = Date().addingTimeInterval(10)
        var visible = false
        repeat {
            let viewport = app.webViews.firstMatch
            let submit = viewport.buttons["Submit"].firstMatch
            let target = viewport.exists && submit.exists ? submit.frame.intersection(viewport.frame) : .null
            let screen = app.screenshot()
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
            try await Task.sleep(nanoseconds: 70_000_000)
        } while Date() < deadline && stop.exists
        XCTAssertTrue(visible, "Expected a connected green marker at the visible Submit button center")
        let result = try await playback.value
        XCTAssertEqual(result["success"] as? Bool, true, "\(result["error"] ?? "")")
        XCTAssertEqual((result["outputs"] as? Body)?["documentTitle"] as? String, "Count 1")
        let geometry = try XCTUnwrap((result["outputs"] as? Body)?["tapGeometry"] as? Body)
        XCTAssertEqual((geometry["fields"] as? [Body])?.first?["values"] as? [String], ["center"])
        let run = try XCTUnwrap(result["runId"] as? String)
        let manifests = try XCTUnwrap(result["artifacts"] as? [Body])
        XCTAssertEqual(manifests.filter { $0["mimeType"] as? String == "image/png" }.count, steps.count)
        XCTAssertEqual(Set(manifests.compactMap { $0["mimeType"] as? String }), ["image/png", "image/gif", "video/mp4"])
        for manifest in manifests { try await inspect(manifest, run: run) }
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
