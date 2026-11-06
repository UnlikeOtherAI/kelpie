import Network
import WebKit
import XCTest
@testable import Kelpie

final class ScriptWorkflowAdmissionTests: XCTestCase {
    typealias Body = [String: Any]
    private let tap: Body = ["action": "tap", "target": ["role": "button", "name": "Submit"]]

    @MainActor
    func testStepOverlayKeepsAdmissionTimeAcrossSlowSnapshot() throws {
        let marker = ScriptOverlayMarker(
            point: CGPoint(x: 25, y: 25),
            started: 100,
            duration: 0.7,
            radius: 12,
            color: ScriptOverlayDrawing.color("#F54242"),
            wobble: false,
            fade: false
        )
        XCTAssertNotNil(ScriptPresentation.exposedMarker(marker, time: 100))
        XCTAssertNotNil(ScriptPresentation.exposedMarker(marker, time: marker.started)) // Held at its admission time.
        XCTAssertNil(ScriptPresentation.exposedMarker(marker, time: 101))
        let admitted = ScriptPresentation.Frame(
            viewport: CGSize(width: 50, height: 50), pointer: nil, marker: marker, commentary: nil, time: 100
        )
        let later = ScriptPresentation.Frame(
            viewport: CGSize(width: 50, height: 50), pointer: nil, marker: marker, commentary: nil, time: 101
        )
        func alpha(_ frame: ScriptPresentation.Frame) throws -> UInt8 {
            let context = try XCTUnwrap(CGContext(
                data: nil,
                width: 50,
                height: 50,
                bitsPerComponent: 8,
                bytesPerRow: 200,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ))
            frame.draw(in: context, size: CGSize(width: 50, height: 50))
            let bytes = try XCTUnwrap(context.data).assumingMemoryBound(to: UInt8.self)
            return bytes[(25 * 50 + 25) * 4 + 3]
        }
        XCTAssertGreaterThan(try alpha(admitted), 0)
        XCTAssertEqual(try alpha(later), 0)
        // The same immutable admission is used even when the renderer returns after its live marker expired.
        XCTAssertGreaterThan(try alpha(admitted), 0)
    }

    @MainActor
    func testStepOverlayRejectsDocumentChangeAfterAdmission() throws {
        var sameDocumentAndGeometry = true
        let current = { sameDocumentAndGeometry }
        XCTAssertNoThrow(try ScriptCapture.requireCurrentOverlay(current))
        sameDocumentAndGeometry = false
        XCTAssertThrowsError(try ScriptCapture.requireCurrentOverlay(current)) { error in
            XCTAssertEqual((error as? ScriptWorkflowFailure)?.code, "CAPTURE_DOCUMENT_CHANGED")
        }
    }

    @MainActor
    func testCoherentCaptureStatePreservesViewportFieldsAndDocument() throws {
        let identity = String(repeating: "a", count: 32)
        let bounds = CGSize(width: 900, height: 700)
        let classic: [NSNumber] = [900, 700, 0, 0, 885, 700, 1, 2, 0, 900, 885, 700]
        let state = try ScriptWorkflowTab.decodeCaptureState(["viewport": classic, "document": identity], bounds: bounds)
        XCTAssertEqual(state.document, identity)
        XCTAssertEqual(state.viewport, try ScriptWorkflowTab.decodeViewport(classic, bounds: bounds))
        XCTAssertEqual(state.viewport.layout, CGSize(width: 900, height: 700))
        XCTAssertEqual(state.viewport.client, CGSize(width: 885, height: 700))
        XCTAssertEqual(state.viewport.visible, CGRect(x: 0, y: 0, width: 885, height: 700))
        XCTAssertEqual(state.viewport.pixelRatio, 2)
        XCTAssertEqual(state.viewport.pageOrigin, CGPoint(x: 0, y: 900))

        let zoomed: [NSNumber] = [900, 700, 30, 40, 450, 350, 2, 2, 130, 240, 900, 700]
        let clipped = try ScriptWorkflowTab.decodeCaptureState(["viewport": zoomed, "document": identity], bounds: bounds)
        XCTAssertEqual(clipped.viewport.visible, CGRect(x: 30, y: 40, width: 450, height: 350))
        XCTAssertEqual(clipped.viewport.scale, 2)
        XCTAssertEqual(clipped.viewport.pageOrigin, CGPoint(x: 130, y: 240))
        XCTAssertNotEqual(state.viewport, clipped.viewport)
        let replacement = try ScriptWorkflowTab.decodeCaptureState(
            ["viewport": classic, "document": String(repeating: "b", count: 32)],
            bounds: bounds
        )
        XCTAssertNotEqual(state.document, replacement.document)
        XCTAssertThrowsError(try ScriptWorkflowTab.decodeCaptureState(["viewport": classic, "document": ""], bounds: bounds))
        XCTAssertThrowsError(try ScriptWorkflowTab.decodeCaptureState(["viewport": [1], "document": identity], bounds: bounds))
    }

    func testOnlyMovieWorkflowsEnterImmersivePresentation() throws {
        XCTAssertFalse(try ScriptBoundWorkflow(workflow([tap])).isImmersive)
        XCTAssertFalse(try ScriptBoundWorkflow(workflow([["action": "screenshot"]])).isImmersive)
        XCTAssertFalse(try ScriptBoundWorkflow(workflow([tap], ["capture": ["formats": ["screenshots"]]])).isImmersive)
        XCTAssertTrue(try ScriptBoundWorkflow(workflow([tap], ["capture": ["formats": ["gif"]]])).isImmersive)
        XCTAssertTrue(try ScriptBoundWorkflow(workflow([tap], ["capture": ["formats": ["video", "screenshots"]]])).isImmersive)
    }

    @MainActor
    func testDisabledNativeChromeRejectsRetainedAccessibilityActions() {
        var presses = 0
        let favourite = FavouriteButton(frame: .zero)
        favourite.activate = { presses += 1 }
        favourite.isEnabled = false
        XCTAssertFalse(favourite.accessibilityPerformPress())
        let toolbar = AppKitToolbarButton.Coordinator { presses += 1 }
        toolbar.isEnabled = false
        toolbar.handlePress()
        let invisible = AppKitInvisibleButton.Coordinator { presses += 1 }
        invisible.isEnabled = false
        invisible.tapped()
        XCTAssertEqual(presses, 0)
        favourite.isEnabled = true
        XCTAssertTrue(favourite.accessibilityPerformPress())
        XCTAssertEqual(presses, 1)
    }

    @MainActor
    func testBonjourTXTReplacementKeepsSameHTTPListenerReachable() async throws {
        let port: UInt16 = 28421
        let router = Router()
        router.register("listener-control") { _ in ["success": true] }
        let pairing = PairingStore(storeURL: nil)
        guard case .created(let pending) = pairing.startPairing(clientId: "listener-control", clientName: "CI", sourceAddress: "127.0.0.1"),
              let token = pairing.approve(requestId: pending.requestId, persist: false)?.token else {
            return XCTFail("Control pairing setup failed")
        }
        let server = try HTTPServer(port: port, router: router, pairingStore: pairing,
                                    deviceInfo: DeviceInfo.current(port: Int(port)))
        let ready = expectation(description: "owned listener ready")
        server.onReady = { [weak server] in server?.onReady = nil; ready.fulfill() }
        server.start()
        defer { server.stop() }
        await fulfillment(of: [ready], timeout: 10)
        let firstIncarnation = try XCTUnwrap(server.scriptListener.incarnation)
        let first = try await Self.probeHTTP(port: port, token: token)
        XCTAssertEqual(first, 200)
        let serviceName = "Kelpie CI " + UUID().uuidString
        server.configureBonjourService(name: serviceName, type: "_kelpie._tcp", txtRecord: NWTXTRecord(["engine": "webkit"]))
        try await Task.sleep(nanoseconds: 500_000_000)
        let afterInitial = try await Self.awaitControlHTTP(port: port, token: token)
        XCTAssertEqual(afterInitial, 200)
        server.configureBonjourService(name: serviceName, type: "_kelpie._tcp", txtRecord: NWTXTRecord(["engine": "chromium"]))
        try await Task.sleep(nanoseconds: 500_000_000)
        let second = try await Self.awaitControlHTTP(port: port, token: token)
        let secondIncarnation = try XCTUnwrap(server.scriptListener.incarnation)
        print("[ListenerControl] recovered=\(firstIncarnation != secondIncarnation ? 1 : 0)")
        XCTAssertEqual(first, 200)
        XCTAssertEqual(second, 200)
        XCTAssertEqual(pairing.validateBearer(token), "listener-control")
        if firstIncarnation != secondIncarnation {
            server.configureBonjourService(name: serviceName, type: "_kelpie._tcp", txtRecord: NWTXTRecord(["engine": "webkit"]))
            try await Task.sleep(nanoseconds: 200_000_000)
            XCTAssertEqual(server.scriptListener.incarnation, secondIncarnation)
            let third = try await Self.awaitControlHTTP(port: port, token: token)
            XCTAssertEqual(third, 200)
        }
    }

    private static func awaitControlHTTP(port: UInt16, token: String) async throws -> Int {
        let deadline = ProcessInfo.processInfo.systemUptime + 4
        while true {
            do { return try await probeHTTP(port: port, token: token) }
            catch let error as URLError where [.cannotConnectToHost, .networkConnectionLost].contains(error.code) {
                guard ProcessInfo.processInfo.systemUptime < deadline else { throw error }
                try await Task.sleep(nanoseconds: 50_000_000)
            }
        }
    }

    private static func probeHTTP(port: UInt16, token: String) async throws -> Int {
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        var request = URLRequest(url: try XCTUnwrap(URL(string: "http://127.0.0.1:\(port)/v1/listener-control")))
        request.timeoutInterval = 3
        request.httpMethod = "POST"
        request.httpBody = Data("{}".utf8)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        request.setValue("close", forHTTPHeaderField: "Connection")
        let (_, response) = try await session.data(for: request)
        return try XCTUnwrap((response as? HTTPURLResponse)?.statusCode)
    }

    func testOnlyServiceNotRunningDNSFailureIsRecoverable() {
        XCTAssertTrue(HTTPListenerFailure.isRecoverableBonjour(.dns(-65563)))
        XCTAssertFalse(HTTPListenerFailure.isRecoverableBonjour(.dns(-65537)))
        XCTAssertFalse(HTTPListenerFailure.isRecoverableBonjour(.posix(.ECONNREFUSED)))
    }

    @MainActor
    func testEmptyPacedTypeRequiresEditableTarget() throws {
        try ScriptWorkflowActions.requireEmptyPacedEditable(["editable": true])
        for value: Any? in [false, nil] {
            var target: Body = [:]
            target["editable"] = value
            XCTAssertThrowsError(try ScriptWorkflowActions.requireEmptyPacedEditable(target)) {
                XCTAssertEqual(($0 as? ScriptWorkflowFailure)?.code, "TARGET_NOT_EDITABLE")
            }
        }
    }

    func testScrollbarTransitionAndProjection() {
        func viewport(client: CGFloat, visible: CGFloat, bounds: CGFloat = 900, scale: CGFloat = 1) -> ScriptCaptureViewport {
            ScriptCaptureViewport(bounds: CGSize(width: bounds, height: 700), layout: CGSize(width: 900, height: 700),
                client: CGSize(width: client, height: 700), visible: CGRect(x: 0, y: 0, width: visible, height: 700),
                scale: scale, pixelRatio: 1, pageOrigin: .zero)
        }
        XCTAssertFalse(ScriptCaptureViewport.confirmedDocumentChange(previous: nil, current: "new"))
        XCTAssertFalse(ScriptCaptureViewport.confirmedDocumentChange(previous: "", current: "new"))
        XCTAssertFalse(ScriptCaptureViewport.confirmedDocumentChange(previous: "old", current: ""))
        XCTAssertFalse(ScriptCaptureViewport.confirmedDocumentChange(previous: "old", current: "old"))
        XCTAssertTrue(ScriptCaptureViewport.confirmedDocumentChange(previous: "old", current: "new"))
        let scrollbar = viewport(client: 883, visible: 883), plain = viewport(client: 900, visible: 900)
        XCTAssertEqual(scrollbar.displayPoint(CGPoint(x: 860, y: 100)).x, 860)
        XCTAssertTrue(scrollbar.acceptsScrollbarTransition(to: plain, documentChanged: true))
        XCTAssertFalse(scrollbar.acceptsScrollbarTransition(to: plain, documentChanged: false))
        XCTAssertFalse(scrollbar.acceptsScrollbarTransition(to: viewport(client: 900, visible: 890), documentChanged: true))
        XCTAssertFalse(scrollbar.acceptsScrollbarTransition(to: viewport(client: 900, visible: 900, bounds: 901), documentChanged: true))
        XCTAssertFalse(scrollbar.acceptsScrollbarTransition(to: viewport(client: 900, visible: 900, scale: 2), documentChanged: true))
    }

    private func workflow(_ steps: [Body], _ extra: Body = [:]) -> Body {
        ["version": 1, "tabId": "test-tab", "actions": steps].merging(extra) { _, new in new }
    }

    private func assertRejected(_ body: Body, _ code: String, line: UInt = #line) {
        XCTAssertThrowsError(try ScriptBoundWorkflow(body), line: line) {
            XCTAssertEqual(($0 as? ScriptWorkflowFailure)?.code, code, line: line)
        }
    }

    func testFullPreflightRejectsForeignSessionsAndUnsupportedKeyAfterTap() throws {
        XCTAssertEqual(try ScriptBoundWorkflow(workflow([tap])).steps.count, 1)
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

    func testPacedEditsPlanBeforeAdmissionAndKeepAtomicDefault() throws {
        let fill: Body = ["action": "fill", "target": ["label": "Draft"], "text": "A😀e\u{301}", "typingDelayMs": 50]
        let type: Body = ["action": "type", "target": ["label": "Draft"], "text": "xy", "typingDelayMs": 20]
        let plan = try ScriptBoundWorkflow(workflow([tap, fill, type]))
        let fillOps = try XCTUnwrap(plan.pacedPlans[1]).operations
        XCTAssertEqual(fillOps.map(\.action), ["fill", "type", "type", "type", "type"])
        XCTAssertEqual(fillOps.map(\.text), ["", "A", "😀", "e", "\u{301}"])
        XCTAssertEqual(fillOps.map(\.delayBeforeMs), [0, 0, 50, 50, 50])
        XCTAssertEqual(fillOps.map(\.requireFocused), [false, true, true, true, true])
        let typeOps = try XCTUnwrap(plan.pacedPlans[2]).operations
        XCTAssertEqual(typeOps.map(\.delayBeforeMs), [0, 20])
        XCTAssertEqual(typeOps.map(\.requireFocused), [false, true])
        let atomic = try ScriptBoundWorkflow(workflow([["action": "type", "target": ["label": "Draft"], "text": "xy"]]))
        XCTAssertTrue(atomic.pacedPlans.isEmpty)
        let emptyType = try ScriptBoundWorkflow(workflow([type.merging(["text": ""]) { _, new in new }]))
        XCTAssertTrue(try XCTUnwrap(emptyType.pacedPlans[0]).operations.isEmpty)
        let emptyFill = try ScriptBoundWorkflow(workflow([fill.merging(["text": ""]) { _, new in new }]))
        XCTAssertEqual(try XCTUnwrap(emptyFill.pacedPlans[0]).operations.map(\.action), ["fill"])
        let oversized = type.merging(["text": String(repeating: "a", count: 1001)]) { _, new in new }
        assertRejected(workflow([tap, oversized]), "INVALID_PACED_TYPING")
        let tooLong = type.merging(["text": String(repeating: "a", count: 1000), "typingDelayMs": 61]) { _, new in new }
        assertRejected(workflow([tap, tooLong]), "INVALID_PACED_TYPING")
    }

    func testSuppliedCaptureDefaultsAndExplicitScreenshotScope() throws {
        let one = try ScriptBoundWorkflow(workflow([tap, ["action": "screenshot"]]))
        XCTAssertFalse(one.stepScreenshots)
        XCTAssertEqual(one.capture?["formats"] as? [String], ["screenshots"])
        let every = try ScriptBoundWorkflow(workflow([tap], ["capture": ["formats": ["screenshots"], "maxBytes": 1024]]))
        XCTAssertTrue(every.stepScreenshots)
        XCTAssertEqual(every.capture?["maxBytes"] as? Int, 1024)
    }

    @MainActor
    func testLateMutatingRendererCallbackRetiresBeforeFurtherAdmission() async throws {
        let renderer = WKWebViewRenderer()
        let lease = BrowserControlLease()
        var complete: CheckedContinuation<Bool, Never>?
        do {
            _ = try await ScriptRendererDeadline.run(renderer: renderer, seconds: 1, mutates: true, lease: lease) {
                await withCheckedContinuation { complete = $0 }
            }
            XCTFail("Timed-out renderer operation returned success")
        } catch let failure as ScriptWorkflowFailure {
            XCTAssertEqual(failure.code, "TIMEOUT")
            XCTAssertTrue(failure.mayHaveCompleted)
        }
        XCTAssertTrue(ScriptRendererDeadline.isRetiring(renderer))
        XCTAssertFalse(lease.begin())
        let late = try XCTUnwrap(complete)
        late.resume(returning: true)
        for _ in 0..<20 where ScriptRendererDeadline.isRetiring(renderer) { await Task.yield() }
        XCTAssertFalse(ScriptRendererDeadline.isRetiring(renderer))
        XCTAssertTrue(lease.begin())
        lease.end()
    }

    @MainActor
    func testOwnedFocusNeverRunsForBackgroundWindow() {
        var calls = 0
        XCTAssertFalse(ScriptWorkflowTab.requestOwnedEditFocus(isKey: false) { calls += 1; return true })
        XCTAssertEqual(calls, 0)
        XCTAssertTrue(ScriptWorkflowTab.requestOwnedEditFocus(isKey: true) { calls += 1; return true })
        XCTAssertEqual(calls, 1)
        XCTAssertFalse(ScriptWorkflowTab.requestOwnedEditFocus(isKey: true) { calls += 1; return false })
        XCTAssertEqual(calls, 2)
    }

    func testIndependentGrantsAndListenerIncarnationsCannotInheritRuns() {
        let listener = ScriptListenerScope()
        let first = listener.start()
        let original = ScriptRequestOwner(listener: first, clientID: "client", bearer: "test-first", isCurrent: { true })
        let replacement = ScriptRequestOwner(listener: first, clientID: "client", bearer: "test-second", isCurrent: { true })
        let second = listener.start()
        let restarted = ScriptRequestOwner(listener: second, clientID: "client", bearer: "test-first", isCurrent: { true })
        listener.stop(first)
        XCTAssertEqual(listener.incarnation, second)
        XCTAssertNotEqual(original.owner, replacement.owner)
        XCTAssertNotEqual(original.owner, restarted.owner)
        XCTAssertFalse(original.owner.contains("test-first"))
        listener.stop(second)
        XCTAssertNil(listener.incarnation)
    }
}
