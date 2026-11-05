import UIKit
import XCTest

extension WorkflowCaptureUITests {
    @MainActor
    func testScriptStopPreservesNonMovieViewportAndMovieImmersion() async throws {
        let (fixture, tab) = try await ready()
        continueAfterFailure = true
        defer { fixture.listener.cancel() }
        let port = try XCTUnwrap(fixture.listener.port?.rawValue)
        let navigation = try await probe.request("/v1/play-script", [
            "version": 1, "tabId": tab, "actions": [["action": "navigate", "url": "http://127.0.0.1:\(port)/projection"]]
        ])
        XCTAssertEqual(navigation["success"] as? Bool, true)
        let modes: [(String, [String]?, Bool, Bool)] = [
            ("No capture", nil, false, false), ("Automatic PNG", ["screenshots"], false, false),
            ("Explicit PNG", nil, true, false), ("GIF", ["gif"], false, true),
            ("Video", ["video"], false, true)
        ]
        let application = XCUIApplication()
        for (name, formats, explicit, movie) in modes {
            let viewport = application.webViews.firstMatch
            let initial = viewport.frame
            let beforeImage = XCTAttachment(screenshot: application.screenshot())
            beforeImage.name = name + " before script"
            beforeImage.lifetime = .keepAlways
            add(beforeImage)
            var actions: [Body] = [["action": "wait", "ms": 10000]]
            if explicit { actions.append(["action": "screenshot", "name": "still"]) }
            var script: Body = ["version": 1, "tabId": tab, "actions": actions]
            if let formats { script["capture"] = ["formats": formats, "fps": 5, "maxWidth": 384] }
            let playback = Task.detached { [probe] in try await probe.request("/v1/play-script", script) }
            let stop = application.buttons["browser.recording.stop"]
            XCTAssertTrue(stop.waitForExistence(timeout: 15), name)
            let during = viewport.frame
            let chrome = application.buttons["browser.more"]
            if movie {
                XCTAssertFalse(chrome.exists, name)
            } else {
                if chrome.exists {
                    XCTAssertFalse(chrome.isEnabled, name)
                    chrome.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
                    XCTAssertTrue(stop.exists, name)
                    XCTAssertFalse(application.buttons["browser.tabs.add"].exists, name)
                }
                XCTAssertEqual(during.minX, initial.minX, accuracy: 0.5, name)
                XCTAssertEqual(during.minY, initial.minY, accuracy: 0.5, name)
                XCTAssertEqual(during.width, initial.width, accuracy: 0.5, name)
                XCTAssertEqual(during.height, initial.height, accuracy: 0.5, name)
            }
            let attachment = XCTAttachment(screenshot: application.screenshot())
            attachment.name = name + " active script and Stop"
            attachment.lifetime = .keepAlways
            add(attachment)
            if name == "No capture" { stop.tap() }
            let result = try await playback.value
            if name == "No capture" {
                XCTAssertEqual((result["error"] as? Body)?["code"] as? String, "SCRIPT_ABORTED")
            } else {
                XCTAssertEqual(result["success"] as? Bool, true, name)
            }
            XCTAssertFalse(stop.exists, name)
            XCTAssertTrue(chrome.waitForExistence(timeout: 5), name)
            let afterImage = XCTAttachment(screenshot: application.screenshot())
            afterImage.name = name + " after script"
            afterImage.lifetime = .keepAlways
            add(afterImage)
            if !movie {
                let after = viewport.frame
                XCTAssertEqual(after.minX, initial.minX, accuracy: 0.5, name)
                XCTAssertEqual(after.minY, initial.minY, accuracy: 0.5, name)
                XCTAssertEqual(after.width, initial.width, accuracy: 0.5, name)
                XCTAssertEqual(after.height, initial.height, accuracy: 0.5, name)
            }
        }
    }
    @MainActor
    func testNonMovieTabletStageRetainsRendererFrame() async throws {
        guard UIDevice.current.userInterfaceIdiom == .pad else { return }
        testLaunchArguments = ["-ipadMobileStagePreset", "compact-base"]
        let (fixture, tab) = try await ready()
        defer { fixture.listener.cancel() }
        let application = XCUIApplication()
        let stage = application.staticTexts["browser.viewport.summary"]
        XCTAssertTrue(stage.waitForExistence(timeout: 10))
        let viewport = application.webViews.firstMatch
        let before = viewport.frame
        let original = XCTAttachment(screenshot: application.screenshot())
        original.name = "Tablet stage before non-movie script"
        original.lifetime = .keepAlways
        add(original)
        let playback = Task.detached { [probe] in
            try await probe.request("/v1/play-script", [
                "version": 1, "tabId": tab, "actions": [["action": "wait", "ms": 5000]],
                "capture": ["formats": ["screenshots"]]
            ])
        }
        let stop = application.buttons["browser.recording.stop"]
        XCTAssertTrue(stop.waitForExistence(timeout: 15))
        let during = viewport.frame
        XCTAssertEqual(during.minX, before.minX, accuracy: 0.5)
        XCTAssertEqual(during.minY, before.minY, accuracy: 0.5)
        XCTAssertEqual(during.width, before.width, accuracy: 0.5)
        XCTAssertEqual(during.height, before.height, accuracy: 0.5)
        let close = application.buttons["browser.viewport.close"]
        if close.exists {
            XCTAssertFalse(close.isEnabled)
            close.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            XCTAssertTrue(stop.exists)
        }
        let active = XCTAttachment(screenshot: application.screenshot())
        active.name = "Tablet stage during non-movie script"
        active.lifetime = .keepAlways
        add(active)
        stop.tap()
        let result = try await playback.value
        XCTAssertEqual((result["error"] as? Body)?["code"] as? String, "SCRIPT_ABORTED")
        XCTAssertTrue(stage.waitForExistence(timeout: 5))
        let afterImage = XCTAttachment(screenshot: application.screenshot())
        afterImage.name = "Tablet stage after non-movie script"
        afterImage.lifetime = .keepAlways
        add(afterImage)
        let after = viewport.frame
        XCTAssertEqual(after.minX, before.minX, accuracy: 0.5)
        XCTAssertEqual(after.minY, before.minY, accuracy: 0.5)
        XCTAssertEqual(after.width, before.width, accuracy: 0.5)
        XCTAssertEqual(after.height, before.height, accuracy: 0.5)
    }

    @MainActor
    func testNonMovieScriptClearsAddressFocus() async throws {
        let (fixture, tab) = try await ready()
        defer { fixture.listener.cancel() }
        let application = XCUIApplication()
        let address = application.textFields["browser.url.field"]
        XCTAssertTrue(address.waitForExistence(timeout: 5))
        address.tap()
        let playback = Task.detached { [probe] in
            try await probe.request("/v1/play-script", [
                "version": 1, "tabId": tab, "actions": [["action": "wait", "ms": 10000]]
            ])
        }
        let stop = application.buttons["browser.recording.stop"]
        XCTAssertTrue(stop.waitForExistence(timeout: 15))
        if address.exists {
            XCTAssertFalse(address.isEnabled)
            address.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            XCTAssertTrue(stop.exists)
        }
        XCTAssertFalse(application.keyboards.firstMatch.exists)
        let attachment = XCTAttachment(screenshot: application.screenshot())
        attachment.name = "Non-movie script after address focus retirement"
        attachment.lifetime = .keepAlways
        add(attachment)
        stop.tap()
        let result = try await playback.value
        XCTAssertEqual((result["error"] as? Body)?["code"] as? String, "SCRIPT_ABORTED")
        XCTAssertTrue(address.waitForExistence(timeout: 5))
    }

    @MainActor
    func testNonMovieLoadingAndScrollKeepChromeGeometry() async throws {
        let (fixture, tab) = try await ready()
        defer { fixture.listener.cancel() }
        let port = try XCTUnwrap(fixture.listener.port?.rawValue)
        let navigation = try await probe.request("/v1/play-script", [
            "version": 1, "tabId": tab, "actions": [["action": "navigate", "url": "http://127.0.0.1:\(port)/scroll"]]
        ])
        XCTAssertEqual(navigation["success"] as? Bool, true)
        let application = XCUIApplication()
        let viewport = application.webViews.firstMatch
        let beforeScroll = viewport.frame
        let scrolling = Task.detached { [probe] in
            try await probe.request("/v1/play-script", [
                "version": 1, "tabId": tab,
                "actions": [["action": "scroll", "deltaX": 0, "deltaY": 450], ["action": "wait", "ms": 5000]]
            ])
        }
        let stop = application.buttons["browser.recording.stop"]
        XCTAssertTrue(stop.waitForExistence(timeout: 15))
        try await Task.sleep(nanoseconds: 500_000_000)
        let afterScroll = viewport.frame
        XCTAssertEqual(afterScroll.minY, beforeScroll.minY, accuracy: 0.5)
        XCTAssertEqual(afterScroll.height, beforeScroll.height, accuracy: 0.5)
        stop.tap()
        let scrollResult = try await scrolling.value
        XCTAssertEqual((scrollResult["error"] as? Body)?["code"] as? String, "SCRIPT_ABORTED")

        let slow = try WorkflowLoopbackPage(responseDelay: 4)
        let slowURL = try await slow.start()
        defer { slow.listener.cancel() }
        let beforeLoad = viewport.frame
        let loading = Task.detached { [probe] in
            try await probe.request("/v1/play-script", [
                "version": 1, "tabId": tab,
                "actions": [["action": "navigate", "url": slowURL], ["action": "wait", "ms": 5000]]
            ])
        }
        XCTAssertTrue(stop.waitForExistence(timeout: 15))
        let deadline = Date().addingTimeInterval(6)
        var sawLoading = false
        repeat {
            if slow.requestCount(path: "/workflow") > 0 && slow.responseCount(path: "/workflow") == 0 {
                let duringLoad = viewport.frame
                if slow.responseCount(path: "/workflow") == 0 {
                    sawLoading = true
                    XCTAssertEqual(duringLoad.minY, beforeLoad.minY, accuracy: 0.5)
                    XCTAssertEqual(duringLoad.height, beforeLoad.height, accuracy: 0.5)
                }
                break
            }
            try await Task.sleep(nanoseconds: 100_000_000)
        } while Date() < deadline
        XCTAssertTrue(sawLoading, "The real delayed fixture load must be observed")
        stop.tap()
        let loadResult = try await loading.value
        XCTAssertEqual((loadResult["error"] as? Body)?["code"] as? String, "SCRIPT_ABORTED")
        XCTAssertEqual(loadResult["mayHaveCompleted"] as? Bool, true)
    }

}
