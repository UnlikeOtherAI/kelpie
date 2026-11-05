import UIKit
import WebKit
import XCTest
@testable import Kelpie

final class IOSWorkflowAdmissionTests: XCTestCase {
    typealias Body = [String: Any]
    private let tap: Body = ["action": "tap", "target": ["role": "button", "name": "Submit"]]

    private func workflow(_ steps: [Body], _ extra: Body = [:]) -> Body {
        ["version": 1, "tabId": "test-tab", "actions": steps].merging(extra) { _, new in new }
    }

    private func assertRejected(_ body: Body, _ code: String, line: UInt = #line) {
        XCTAssertThrowsError(try IOSBoundWorkflow(body), line: line) {
            XCTAssertEqual(($0 as? IOSWorkflowFailure)?.code, code, line: line)
        }
    }

    @MainActor
    func testCaptureCleanupPreservesRegisteredAliasAndDiscardsUnpublishedFiles() throws {
        let manager = FileManager.default
        let base = manager.temporaryDirectory.appendingPathComponent("ios-capture-cleanup-" + UUID().uuidString)
        let real = base.appendingPathComponent("real")
        let alias = base.appendingPathComponent("alias")
        let directory = real.appendingPathComponent("run")
        try manager.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: base) }
        try manager.createSymbolicLink(at: alias, withDestinationURL: real)
        let retained = alias.appendingPathComponent("run/retained.png")
        let discarded = directory.appendingPathComponent("unpublished.png")
        let bytes = Data([1, 3, 5, 7])
        try bytes.write(to: retained)
        try Data([2, 4]).write(to: discarded)
        let entries = try manager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        XCTAssertFalse(entries.contains(retained), "The test must use different path spellings")
        let run = UUID().uuidString
        let manifest = try ScriptArtifactStore.shared.add(url: retained, runID: run, mimeType: "image/png", owner: "owner")
        let id = try XCTUnwrap(manifest["id"] as? String)
        let request: Body = ["runId": run, "artifactId": id, "offset": 0, "length": 4]

        IOSCaptureCleanup.prune(directory: directory, retaining: [retained])
        let owned = ScriptArtifactStore.shared.read(request, owner: "owner")
        XCTAssertEqual(owned["data"] as? String, bytes.base64EncodedString())
        XCTAssertEqual((ScriptArtifactStore.shared.read(request, owner: "foreign")["error"] as? Body)?["code"] as? String,
                       "ARTIFACT_NOT_FOUND")
        XCTAssertFalse(manager.fileExists(atPath: discarded.path))

        // Privacy discard publishes no files: the retained set is empty.
        IOSCaptureCleanup.prune(directory: directory, retaining: [])
        XCTAssertFalse(manager.fileExists(atPath: directory.path))
        XCTAssertEqual((ScriptArtifactStore.shared.read(request, owner: "owner")["error"] as? Body)?["code"] as? String,
                       "ARTIFACT_READ_FAILED")
    }

    @MainActor
    func testFirstCaptureWaitsForStableCompleteViewport() {
        func viewport(height: CGFloat, scale: CGFloat = 1, offset: CGFloat = 0) -> IOSWorkflowTab.Viewport {
            IOSWorkflowTab.Viewport(bounds: CGSize(width: 390, height: 800),
                                    layout: CGSize(width: 390, height: height),
                                    visible: CGRect(x: 0, y: offset, width: 390, height: height),
                                    scale: scale, pixelRatio: 3)
        }
        var stability = IOSCaptureViewportStability()
        XCTAssertFalse(stability.observe(viewport(height: 780), at: 0))
        XCTAssertFalse(stability.observe(viewport(height: 780), at: 0.19))
        XCTAssertFalse(stability.observe(viewport(height: 760), at: 0.20))
        XCTAssertFalse(stability.observe(viewport(height: 760), at: 0.39))
        XCTAssertTrue(stability.observe(viewport(height: 760), at: 0.41))
        XCTAssertFalse(stability.observe(viewport(height: 760, offset: 10), at: 0.42))
        XCTAssertFalse(stability.observe(viewport(height: 760, scale: 1.5, offset: 10), at: 0.70))
        XCTAssertTrue(stability.observe(viewport(height: 760, scale: 1.5, offset: 10), at: 0.91))
    }

    @MainActor
    func testFirstCaptureStabilityHonorsTimeoutStopAndDocumentReplacement() async throws {
        let viewport = IOSWorkflowTab.Viewport(bounds: CGSize(width: 390, height: 800),
                                               layout: CGSize(width: 390, height: 800),
                                               visible: CGRect(x: 0, y: 0, width: 390, height: 800),
                                               scale: 1, pixelRatio: 3)
        var time = 0.0
        do {
            _ = try await IOSCaptureViewportStability.wait(
                deadline: 0.1, check: {}, read: { viewport }, now: { time }, pause: { time += 0.02 }
            )
            XCTFail("Unsettled viewport must reach the existing deadline")
        } catch {
            XCTAssertEqual((error as? IOSWorkflowFailure)?.code, "CAPTURE_VIEWPORT_UNSTABLE")
        }

        var checks = 0
        do {
            _ = try await IOSCaptureViewportStability.wait(
                deadline: 1, check: {
                    checks += 1
                    if checks > 2 { throw IOSWorkflowFailure("SCRIPT_ABORTED") }
                }, read: { viewport }, now: { time }, pause: { time += 0.02 }
            )
            XCTFail("Stop must interrupt admission")
        } catch {
            XCTAssertEqual((error as? IOSWorkflowFailure)?.code, "SCRIPT_ABORTED")
        }

        var reads = 0
        var replacementChecks = 0
        let replaced = try await IOSCaptureViewportStability.wait(
            deadline: 1, check: { replacementChecks += 1 }, read: { reads += 1; return nil },
            now: { time }, pause: { XCTFail("No retry after replacement") }
        )
        XCTAssertNil(replaced)
        XCTAssertEqual(reads, 1)
        XCTAssertEqual(replacementChecks, 2)
    }

    @MainActor
    func testWorkflowReadInspectsRealSelectedTabWhilePublicGateRemainsClosed() async throws {
        let context = HandlerContext()
        let view = WKWebView(frame: CGRect(x: 0, y: 0, width: 390, height: 640))
        let container = UIView(frame: view.frame)
        container.addSubview(view)
        let tab = BrowserTab(webView: view, recordsHistory: false)
        let store = TabStore(isolatedTab: tab)
        context.webView = view
        context.tabStore = store
        let router = Router()
        let playback = ScriptPlaybackState()
        router.handlerContext = context
        router.scriptPlaybackState = playback
        MobileTabHandler(context: context).register(on: router)
        view.loadHTMLString("<body><p id='fixture'>workflow read ready</p></body>", baseURL: nil)
        defer { view.stopLoading(); withExtendedLifetime(container) {} }
        let deadline = Date().addingTimeInterval(10)
        var loaded = false
        repeat {
            loaded = (try? await BrowserControlWebKit.evaluate("document.body?.textContent", in: view) as? String) == "workflow read ready"
            if !loaded { try await Task.sleep(nanoseconds: 50_000_000) }
        } while !loaded && Date() < deadline
        XCTAssertTrue(loaded)
        guard loaded else { return }
        XCTAssertTrue(playback.start(totalActions: 1, continueOnError: false))
        defer { _ = playback.finishSuccess() }

        let blocked = await router.handle(method: "get-tabs", body: [:], browserGatewayDispatch: true).json
        XCTAssertEqual((blocked["error"] as? Body)?["code"] as? String, "RECORDING_IN_PROGRESS")
        let request: Body = ["version": 1, "method": "tab.ready", "tabId": tab.id.uuidString,
                             "params": ["state": "complete", "selector": "#fixture"]]
        let unscoped = await router.browserControl(request)
        XCTAssertEqual((unscoped["error"] as? Body)?["code"] as? String, "COMMAND_FAILED")

        let ready = await router.workflowRead(method: "tab.ready", tabID: tab.id.uuidString,
                                              params: ["state": "complete", "selector": "#fixture"])
        XCTAssertEqual(ready["ok"] as? Bool, true)
        XCTAssertEqual((ready["value"] as? Body)?["ready"] as? Bool, true)
        let extracted = await router.workflowRead(method: "tab.extract", tabID: tab.id.uuidString,
                                                  params: ["fields": [["name": "text", "selector": "#fixture", "source": "text"]]])
        let value = try XCTUnwrap(extracted["value"] as? Body)
        let fields = try XCTUnwrap(value["fields"] as? [Body])
        XCTAssertEqual(fields.first?["values"] as? [String], ["workflow read ready"])
        let denied = await router.workflowRead(method: "tab.click", tabID: tab.id.uuidString, params: [:])
        XCTAssertEqual((denied["error"] as? Body)?["code"] as? String, "UNSUPPORTED")
        let stillBlocked = await router.handle(method: "get-tabs", body: [:], browserGatewayDispatch: true).json
        XCTAssertEqual((stillBlocked["error"] as? Body)?["code"] as? String, "RECORDING_IN_PROGRESS")
        withExtendedLifetime(store) {}
    }

    func testDeviceCapabilitiesAdvertiseOnlySupportedMobileActions() throws {
        let enabled = IOSBoundWorkflow.deviceCapabilities(videoAvailable: true)
        let disabled = IOSBoundWorkflow.deviceCapabilities(videoAvailable: false)
        let actions = try XCTUnwrap(enabled["supportedActions"] as? [String])
        XCTAssertEqual(actions, ["assert", "click", "commentary", "extract", "fill", "navigate", "output",
                                 "screenshot", "scroll", "tap", "type", "wait", "wait-ready"])
        XCTAssertFalse(actions.contains("press-key"))
        XCTAssertEqual(enabled["captureFormats"] as? [String], ["gif", "screenshots", "video"])
        XCTAssertEqual(disabled["captureFormats"] as? [String], ["gif", "screenshots"])
        XCTAssertEqual(enabled["nativeSessions"] as? Bool, false)
        XCTAssertEqual((enabled["webMcp"] as? Body)?["available"] as? Bool, false)
        XCTAssertEqual((enabled["lightpanda"] as? Body)?["available"] as? Bool, false)
    }

    func testPointerDefaultAndExplicitDurationUseSharedContract() throws {
        let defaulted = try IOSBoundWorkflow(workflow([tap], ["pointer": ["enabled": true]]))
        let normal = try XCTUnwrap(defaulted.settings["pointer"] as? Body)
        XCTAssertEqual(normal["durationMs"] as? Int, 350)
        XCTAssertEqual(normal["curve"] as? String, "s")
        XCTAssertEqual(normal["easing"] as? String, "ease-in-out")

        let explicit = try IOSBoundWorkflow(workflow([tap], [
            "pointer": ["enabled": true, "curve": "c", "durationMs": 2400, "easing": "ease-in-out"]
        ]))
        let requested = try XCTUnwrap(explicit.settings["pointer"] as? Body)
        XCTAssertEqual(requested["durationMs"] as? Int, 2400)
        XCTAssertEqual(requested["curve"] as? String, "c")
        XCTAssertEqual(requested["easing"] as? String, "ease-in-out")
    }

    @MainActor
    func testPacedExecutorClearsOnceAndWaitsOnlyBetweenUnicodeScalars() async throws {
        var events: [String] = []
        try await IOSPacedTypingExecutor.run(
            clearFirst: true,
            scalars: ["A", "\u{1F600}"],
            delayMs: 25,
            apply: { action, text, focused, _ in events.append("\(action):\(text):\(focused)") },
            wait: { delay in events.append("wait:\(delay)") }
        )
        XCTAssertEqual(events, ["fill::false", "type:A:true", "wait:25", "type:\u{1F600}:true"])
        events = []
        try await IOSPacedTypingExecutor.run(
            clearFirst: false,
            scalars: ["A", "B"],
            delayMs: 25,
            apply: { action, text, focused, _ in events.append("\(action):\(text):\(focused)") },
            wait: { delay in events.append("wait:\(delay)") }
        )
        XCTAssertEqual(events, ["type:A:false", "wait:25", "type:B:true"])
        events = []
        try await IOSPacedTypingExecutor.run(
            clearFirst: false, scalars: [], delayMs: 25,
            apply: { _, _, _, _ in events.append("input") }, wait: { _ in events.append("wait") }
        )
        XCTAssertTrue(events.isEmpty)
        try await IOSPacedTypingExecutor.run(
            clearFirst: true, scalars: [], delayMs: 25,
            apply: { action, text, focused, _ in events.append("\(action):\(text):\(focused)") },
            wait: { _ in events.append("wait") }
        )
        XCTAssertEqual(events, ["fill::false"])
    }

    @MainActor
    func testPacedExecutorStopsWithoutReplayAndPreservesUncertainty() async {
        var writes = 0
        do {
            try await IOSPacedTypingExecutor.run(
                clearFirst: false, scalars: ["A", "B"], delayMs: 25,
                apply: { _, _, _, _ in writes += 1 }, wait: { _ in throw IOSWorkflowFailure("SCRIPT_ABORTED") }
            )
            XCTFail("Stop must interrupt before the second scalar")
        } catch let failure as IOSWorkflowFailure {
            XCTAssertEqual(failure.code, "SCRIPT_ABORTED")
            XCTAssertTrue(failure.mayHaveCompleted)
        } catch { XCTFail("Unexpected failure type") }
        XCTAssertEqual(writes, 1)

        do {
            try await IOSPacedTypingExecutor.run(
                clearFirst: false, scalars: ["A"], delayMs: 25,
                apply: { _, _, _, _ in throw IOSWorkflowFailure("STALE_TARGET") }, wait: { _ in XCTFail("No wait") }
            )
            XCTFail("Target refusal must stop input")
        } catch let failure as IOSWorkflowFailure {
            XCTAssertEqual(failure.code, "STALE_TARGET")
            XCTAssertFalse(failure.mayHaveCompleted)
        } catch { XCTFail("Unexpected failure type") }

        do {
            try await IOSPacedTypingExecutor.run(
                clearFirst: false, scalars: ["A"], delayMs: 25,
                apply: { _, _, _, _ in throw IOSWorkflowFailure("INPUT_UNCERTAIN", mayHaveCompleted: true) },
                wait: { _ in XCTFail("No wait") }
            )
            XCTFail("Unknown input must not be retried")
        } catch let failure as IOSWorkflowFailure {
            XCTAssertEqual(failure.code, "INPUT_UNCERTAIN")
            XCTAssertTrue(failure.mayHaveCompleted)
        } catch { XCTFail("Unexpected failure type") }
    }

    @MainActor
    func testPacedAcknowledgementRequiresCompleteResultAndMatchingToken() throws {
        let valid: Body = ["ok": true, "sensitive": false, "sensitivityKnown": true,
                           "mayHaveCompleted": true, "token": "t1", "inputGuarantee": "synthetic-coordinate"]
        XCTAssertTrue(IOSPacedTypingExecutor.isAcknowledgement(valid, token: "t1"))
        var unknown = valid
        unknown["sensitivityKnown"] = false
        XCTAssertTrue(IOSPacedTypingExecutor.isAcknowledgement(unknown, token: "t1"))
        XCTAssertFalse(IOSPacedTypingExecutor.isAcknowledgement(valid, token: "t2"))
        XCTAssertFalse(IOSPacedTypingExecutor.needsPrivacyLatch(valid, token: "t1"))
        XCTAssertTrue(IOSPacedTypingExecutor.needsPrivacyLatch(valid, token: "t2"))
        var refusal = valid
        refusal["ok"] = false
        refusal["error"] = "TARGET_MOVED"
        refusal["mayHaveCompleted"] = false
        XCTAssertFalse(IOSPacedTypingExecutor.needsPrivacyLatch(refusal, token: "t1"))
        refusal["mayHaveCompleted"] = true
        XCTAssertFalse(IOSPacedTypingExecutor.needsPrivacyLatch(refusal, token: "t1"))
        refusal["error"] = ""
        XCTAssertTrue(IOSPacedTypingExecutor.needsPrivacyLatch(refusal, token: "t1"))
        XCTAssertFalse(IOSPacedTypingExecutor.isAcknowledgement(valid, token: nil))
        XCTAssertFalse(IOSPacedTypingExecutor.isAcknowledgement(valid, token: ""))
        var contradiction = valid
        contradiction["error"] = "INPUT_UNCERTAIN"
        XCTAssertFalse(IOSPacedTypingExecutor.isAcknowledgement(contradiction, token: "t1"))
        contradiction["error"] = NSNull()
        XCTAssertFalse(IOSPacedTypingExecutor.isAcknowledgement(contradiction, token: "t1"))
        XCTAssertTrue(IOSPacedTypingExecutor.needsPrivacyLatch(contradiction, token: "t1"))
        XCTAssertTrue(IOSPacedTypingExecutor.hasKnownSensitivity(["sensitive": true, "sensitivityKnown": false]))
        XCTAssertFalse(IOSPacedTypingExecutor.hasKnownSensitivity(["sensitive": false, "sensitivityKnown": false]))
        XCTAssertFalse(IOSPacedTypingExecutor.hasKnownSensitivity(["sensitivityKnown": true]))
        XCTAssertFalse(IOSPacedTypingExecutor.hasKnownSensitivity(["sensitive": "false", "sensitivityKnown": true]))
        var wrongGuarantee = valid
        wrongGuarantee["inputGuarantee"] = "trusted"
        XCTAssertFalse(IOSPacedTypingExecutor.isAcknowledgement(wrongGuarantee, token: "t1"))
        let malformedValues = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: Data("[1,0,\"true\",null]".utf8)) as? [Any]
        )
        for field in ["ok", "sensitive", "sensitivityKnown", "mayHaveCompleted"] {
            for value in malformedValues {
                var malformed = valid
                malformed[field] = value
                XCTAssertFalse(IOSPacedTypingExecutor.isAcknowledgement(malformed, token: "t1"))
                XCTAssertTrue(IOSPacedTypingExecutor.needsPrivacyLatch(malformed, token: "t1"))
            }
        }
        for key in ["ok", "sensitive", "sensitivityKnown", "mayHaveCompleted", "token", "inputGuarantee"] {
            var malformed = valid
            malformed.removeValue(forKey: key)
            XCTAssertFalse(IOSPacedTypingExecutor.isAcknowledgement(malformed, token: "t1"))
        }
    }

    @MainActor
    func testPacedUnknownPostMutationSensitivityStops() throws {
        try IOSPacedTypingExecutor.requireKnownSensitivity(true, hasContinuation: true)
        try IOSPacedTypingExecutor.requireKnownSensitivity(false, hasContinuation: false)
        try IOSPacedTypingExecutor.requireKnownSensitivity(nil, hasContinuation: false)
        for known in [false, nil] as [Bool?] {
            XCTAssertThrowsError(try IOSPacedTypingExecutor.requireKnownSensitivity(known, hasContinuation: true)) { error in
                let failure = error as? IOSWorkflowFailure
                XCTAssertEqual(failure?.code, "INPUT_UNCERTAIN")
                XCTAssertEqual(failure?.mayHaveCompleted, true)
            }
        }
    }

    func testPacedEditsArePlannedBeforeAnyEarlierAction() throws {
        let target: Body = ["label": "Entry"]
        let text = "e\u{0301}\u{1F600}"
        let delayed: Body = ["action": "fill", "target": target, "text": text, "typingDelayMs": 20]
        let planned = try IOSBoundWorkflow(workflow([tap, delayed]))
        XCTAssertNil(planned.pacedPlans[0])
        let plan = try XCTUnwrap(planned.pacedPlans[1])
        XCTAssertTrue(plan.clearFirst)
        XCTAssertEqual(plan.delayMs, 20)
        XCTAssertEqual(plan.scalars, ["e", "\u{0301}", "\u{1F600}"])

        let atomic: Body = ["action": "fill", "target": target, "text": "abc"]
        XCTAssertTrue(try IOSBoundWorkflow(workflow([atomic])).pacedPlans.isEmpty)
        let emptyFill = try IOSBoundWorkflow(workflow([delayed.merging(["text": ""]) { _, new in new }]))
        XCTAssertEqual(emptyFill.pacedPlans[0]?.clearFirst, true)
        XCTAssertEqual(emptyFill.pacedPlans[0]?.scalars, [])
        let emptyType = try IOSBoundWorkflow(workflow([delayed.merging(["action": "type", "text": ""]) { _, new in new }]))
        XCTAssertEqual(emptyType.pacedPlans[0]?.clearFirst, false)
        XCTAssertEqual(emptyType.pacedPlans[0]?.scalars, [])

        let tooMany = delayed.merging(["text": String(repeating: "a", count: 1001)]) { _, new in new }
        assertRejected(workflow([tap, tooMany]), "INVALID_PACED_TYPING")
        let tooLong = delayed.merging(["text": String(repeating: "a", count: 62), "typingDelayMs": 1000]) { _, new in new }
        assertRejected(workflow([tap, tooLong]), "INVALID_PACED_TYPING")
    }

    func testFullPreflightRejectsForeignSessionsAndUnsupportedKeyAfterTap() throws {
        XCTAssertEqual(try IOSBoundWorkflow(workflow([tap])).steps.count, 1)
        for session in ["unknown-session", "other-owner-session"] {
            assertRejected(workflow([tap], ["sessionId": session]), "SESSION_UNSUPPORTED")
        }
        assertRejected(workflow([tap, ["action": "press-key", "key": "Enter"]]), "UNSUPPORTED_SCRIPT_ACTION")
        assertRejected(workflow([tap], ["continueOnError": true]), "INVALID_SCRIPT")
        assertRejected(workflow([tap], ["inputs": ["unused": ["type": "string", "required": true]]]), "UNRESOLVED_INPUT")
    }

    func testUnresolvedAndSensitiveCaptureFailuresPrecedeRendererAdmission() {
        let fill: Body = ["action": "fill", "target": ["label": "Password"], "text": "fixture-only", "sensitive": true]
        assertRejected(workflow([tap, fill, ["action": "screenshot"]]), "SENSITIVE_CAPTURE_REFUSED")
        assertRejected(workflow([fill], ["capture": ["formats": ["gif"]]]), "SENSITIVE_CAPTURE_REFUSED")
        assertRejected(workflow([tap, fill.merging(["text": ["secret": "private"]]) { _, new in new }]), "UNRESOLVED_INPUT")
    }

    func testLateStopPreservesSensitiveRefusalAndUncertainInput() {
        let privacy = IOSWorkflowFailure("SENSITIVE_CAPTURE_REFUSED")
        let input = IOSWorkflowFailure("INPUT_UNCERTAIN", mayHaveCompleted: true)
        let capture = IOSWorkflowFailure("CAPTURE_BUDGET_EXCEEDED")
        XCTAssertEqual(IOSWorkflowFailure.terminal(action: privacy, capture: capture, stopRequested: true)?.code, privacy.code)
        let uncertain = IOSWorkflowFailure.terminal(action: input, capture: nil, stopRequested: true)
        XCTAssertEqual(uncertain?.code, input.code)
        XCTAssertTrue(uncertain?.mayHaveCompleted == true)
        XCTAssertEqual(IOSWorkflowFailure.terminal(action: nil, capture: capture, stopRequested: true)?.code, capture.code)
        XCTAssertEqual(IOSWorkflowFailure.terminal(action: nil, capture: nil, stopRequested: true)?.code, "SCRIPT_ABORTED")
        XCTAssertNil(IOSWorkflowFailure.terminal(action: nil, capture: nil, stopRequested: false))
    }

    func testSuppliedCaptureDefaultsAndExplicitScreenshotScope() throws {
        let one = try IOSBoundWorkflow(workflow([tap, ["action": "screenshot"]]))
        XCTAssertFalse(one.stepScreenshots)
        XCTAssertEqual(one.capture?["formats"] as? [String], ["screenshots"])
        let every = try IOSBoundWorkflow(workflow([tap], ["capture": ["formats": ["screenshots"], "maxBytes": 1024]]))
        XCTAssertTrue(every.stepScreenshots)
        XCTAssertEqual(every.capture?["maxBytes"] as? Int, 1024)
    }

    @MainActor
    func testNavigationReservesAfterAuthorizationAndKeepsItsPinnedView() async throws {
        let pinned = NSObject(), otherView = NSObject(), navigation = NSObject()
        let initial = ConnectDocument.version(pinned)
        defer { ConnectDocument.reserve(pinned, lease: nil) }
        let lease = try await IOSWorkflowNavigation.issue(on: pinned, authorize: {
            // A prior provisional callback may arrive while grant authorization is suspended.
            await Task.yield()
            ConnectDocument.navigated(pinned, navigation: NSObject())
        }, load: { navigation })
        XCTAssertNotEqual(ConnectDocument.version(pinned), initial)
        XCTAssertTrue(lease.allowsWait(version: ConnectDocument.version(pinned), authorized: true))
        ConnectDocument.navigated(otherView, navigation: NSObject())
        ConnectDocument.navigated(pinned, navigation: navigation)
        let destination = ConnectDocument.version(pinned)
        XCTAssertTrue(lease.allowsRead(version: destination, loading: false, authorized: true))
        XCTAssertFalse(lease.allowsRead(version: destination, loading: false, authorized: false))
        ConnectDocument.navigated(pinned, navigation: NSObject())
        XCTAssertFalse(lease.allowsWait(version: ConnectDocument.version(pinned), authorized: true))
    }

    @MainActor
    func testDeniedNavigationNeverReservesOrLoadsTheView() async throws {
        let pinned = NSObject(), navigation = NSObject()
        let existing = ConnectNavigationLease(initial: ConnectDocument.version(pinned))
        ConnectDocument.reserve(pinned, lease: existing)
        ConnectDocument.issued(pinned, navigation: navigation)
        defer { ConnectDocument.reserve(pinned, lease: nil) }
        var loaded = false
        do {
            _ = try await IOSWorkflowNavigation.issue(on: pinned, authorize: {
                throw IOSWorkflowFailure("AUTHORIZATION_REVOKED")
            }, load: { loaded = true; return NSObject() })
            XCTFail("Revoked authorization issued a navigation")
        } catch let error as IOSWorkflowFailure { XCTAssertEqual(error.code, "AUTHORIZATION_REVOKED") }
        XCTAssertFalse(loaded)
        ConnectDocument.navigated(pinned, navigation: navigation)
        XCTAssertTrue(existing.allowsRead(version: ConnectDocument.version(pinned), loading: false, authorized: true))
    }

    @MainActor
    func testLateMutatingRendererCallbackRetiresBeforeFurtherAdmission() async throws {
        let view = WKWebView()
        let lease = BrowserControlLease()
        var complete: CheckedContinuation<Bool, Never>?
        do {
            _ = try await IOSRendererDeadline.run(view: view, seconds: 1, mutates: true, lease: lease) {
                await withCheckedContinuation { complete = $0 }
            }
            XCTFail("Timed-out renderer operation returned success")
        } catch let failure as IOSWorkflowFailure {
            XCTAssertEqual(failure.code, "TIMEOUT")
            XCTAssertTrue(failure.mayHaveCompleted)
        }
        XCTAssertTrue(IOSRendererDeadline.isRetiring(view))
        XCTAssertFalse(lease.begin())
        let late = try XCTUnwrap(complete)
        late.resume(returning: true)
        for _ in 0..<20 where IOSRendererDeadline.isRetiring(view) { await Task.yield() }
        XCTAssertFalse(IOSRendererDeadline.isRetiring(view))
        XCTAssertTrue(lease.begin())
        lease.end()
    }

    func testIndependentGrantsAndListenerIncarnationsCannotInheritRuns() {
        let listener = IOSScriptListener()
        let first = listener.start()
        let original = IOSScriptGrant(listener: first, clientID: "client", bearer: "test-first", isCurrent: { true })
        let replacement = IOSScriptGrant(listener: first, clientID: "client", bearer: "test-second", isCurrent: { true })
        let second = listener.start()
        let restarted = IOSScriptGrant(listener: second, clientID: "client", bearer: "test-first", isCurrent: { true })
        listener.stop(first)
        XCTAssertEqual(listener.incarnation, second)
        XCTAssertNotEqual(original.owner, replacement.owner)
        XCTAssertNotEqual(original.owner, restarted.owner)
        XCTAssertFalse(original.owner.contains("test-first"))
        listener.stop(second)
        XCTAssertNil(listener.incarnation)
    }
}
