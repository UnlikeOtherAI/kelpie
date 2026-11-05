import UIKit
import WebKit
import XCTest
@testable import Kelpie

final class IOSWorkflowNavigationTests: XCTestCase {
    private var phase = "setup"
    private var diagnosticLease: ConnectNavigationLease?
    @MainActor
    private func withView(_ operation: (WKWebView) async throws -> Void) async throws {
        let view = WKWebView(frame: CGRect(x: 0, y: 0, width: 390, height: 640))
        let container = UIView(frame: view.frame)
        let context = HandlerContext()
        let coordinator = TabWebViewContainer.Coordinator(
            browserState: BrowserState(), handlerContext: context,
            onScrollDirectionChange: { _ in }, onWebViewReady: { _ in }
        )
        coordinator.install(webView: view, in: container)
        let began = ProcessInfo.processInfo.systemUptime
        var primary = "none"
        defer {
            let report: [String: Any] = [
                "phase": phase, "primary": primary, "loading": view.isLoading,
                "elapsedMs": Int((ProcessInfo.processInfo.systemUptime - began) * 1000)
            ]
            if let data = try? JSONSerialization.data(withJSONObject: report, options: [.sortedKeys]) {
                let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
                attachment.name = "Navigation fixture state before teardown"
                attachment.lifetime = .keepAlways
                add(attachment)
            }
            if let diagnosticLease { attach(diagnosticLease, name: "Last lease before fixture teardown") }
            view.stopLoading()
            ConnectDocument.reserve(view, lease: nil)
            withExtendedLifetime((container, coordinator)) {}
        }
        do { try await operation(view) } catch {
            primary = (error as? IOSWorkflowFailure)?.code ?? String(reflecting: type(of: error))
            throw error
        }
    }

    @MainActor
    private func startPrior(_ address: String, view: WKWebView) throws -> ConnectNavigationLease {
        let prior = ConnectNavigationLease(initial: ConnectDocument.version(view))
        diagnosticLease = prior
        ConnectDocument.reserve(view, lease: prior)
        let token = try XCTUnwrap(view.load(URLRequest(url: try XCTUnwrap(URL(string: address)))))
        ConnectDocument.issued(view, navigation: token)
        return prior
    }

    @MainActor
    func testRealWebKitHTTPNavigationUsesIssuedToken() async throws {
        try await navigate(priorURL: nil)
    }

    @MainActor
    func testRealWebKitHTTPNavigationAfterPriorBlankUsesIssuedToken() async throws {
        try await navigate(priorURL: "about:blank")
    }

    @MainActor
    func testRealWebKitDelayedPriorHTTPCallbackRetiresBeforeNewLease() async throws {
        let previous = try WorkflowLoopbackPage(responseDelay: 0.4)
        let address = try await previous.start()
        defer { previous.listener.cancel() }
        try await navigate(priorURL: address, warmup: true)
    }

    @MainActor
    private func navigate(priorURL: String?, warmup: Bool = false) async throws {
        let fixture = try WorkflowLoopbackPage()
        let address = try await fixture.start()
        defer { fixture.listener.cancel() }
        try await withView { view in
            if warmup {
                phase = "warmup"
                let warm = try startPrior(address + "?warmup=1", view: view)
                let end = ContinuousClock.now.advanced(by: .seconds(20))
                while warm.allowsWait(version: ConnectDocument.version(view), authorized: true),
                      !warm.allowsRead(version: ConnectDocument.version(view), loading: view.isLoading, authorized: true),
                      ContinuousClock.now < end {
                    try await Task.sleep(nanoseconds: 50_000_000)
                }
                guard warm.allowsRead(version: ConnectDocument.version(view), loading: view.isLoading, authorized: true) else {
                    throw IOSWorkflowFailure("FIXTURE_WARMUP_FAILED")
                }
                attach(warm, name: "Warmup exact callback retired")
            }
            phase = "prior-load"
            let prior = try priorURL.map { try startPrior($0, view: view) }
            let url = try XCTUnwrap(URL(string: address))
            phase = "admission"
            let lease = try await IOSWorkflowNavigation.issue(on: view, authorize: {}, isLoading: { view.isLoading }) {
                phase = "load-issued"
                if let prior {
                    // The old lease can read only after its exact WKNavigation callback was consumed.
                    XCTAssertTrue(prior.allowsRead(version: ConnectDocument.version(view), loading: view.isLoading, authorized: true))
                    attach(prior, name: "Prior callback state before replacement load")
                }
                return view.load(URLRequest(url: url))
            }
            diagnosticLease = lease
            phase = "waiting-own-load"
            let deadline = Date().addingTimeInterval(12)
            while lease.allowsWait(version: ConnectDocument.version(view), authorized: true),
                  !lease.allowsRead(version: ConnectDocument.version(view), loading: view.isLoading, authorized: true),
                  Date() < deadline {
                try await Task.sleep(nanoseconds: 50_000_000)
            }
            attach(lease, name: "Real HTTP navigation lease state")
            XCTAssertTrue(lease.allowsWait(version: ConnectDocument.version(view), authorized: true))
            XCTAssertTrue(lease.allowsRead(version: ConnectDocument.version(view), loading: view.isLoading, authorized: true))
            XCTAssertEqual(view.title, "Count 0")
            phase = "completed"
        }
    }

    @MainActor
    func testRealWebKitPriorLoadDeadlineDoesNotIssueAnotherLoad() async throws {
        let fixture = try WorkflowLoopbackPage(responseDelay: 2)
        let address = try await fixture.start()
        defer { fixture.listener.cancel() }
        try await withView { view in
            _ = try startPrior(address, view: view)
            var loaded = false
            do {
                _ = try await IOSWorkflowNavigation.issue(
                    on: view, deadline: .now.advanced(by: .milliseconds(150)),
                    authorize: {}, isLoading: { view.isLoading }, load: { loaded = true; return nil }
                )
                XCTFail("An unsettled prior load was admitted")
            } catch let error as IOSWorkflowFailure {
                XCTAssertEqual(error.code, "NAVIGATION_BUSY")
                XCTAssertFalse(error.mayHaveCompleted)
            }
            XCTAssertFalse(loaded)
        }
    }

    @MainActor
    func testRealWebKitPriorLoadCancellationDoesNotIssueAnotherLoad() async throws {
        let fixture = try WorkflowLoopbackPage(responseDelay: 2)
        let address = try await fixture.start()
        defer { fixture.listener.cancel() }
        try await withView { view in
            _ = try startPrior(address, view: view)
            var loaded = false
            let attempt = Task { @MainActor in
                try await IOSWorkflowNavigation.issue(
                    on: view, authorize: {}, isLoading: { view.isLoading },
                    load: { loaded = true; return nil }
                )
            }
            try await Task.sleep(nanoseconds: 100_000_000)
            attempt.cancel()
            do {
                _ = try await attempt.value
                XCTFail("A canceled prior-load wait issued a new load")
            } catch let error as IOSWorkflowFailure { XCTAssertEqual(error.code, "SCRIPT_ABORTED") }
            XCTAssertFalse(loaded)
        }
    }

    @MainActor
    func testRealWebKitForeignCallbackAfterReservationStillRefuses() async throws {
        let fixture = try WorkflowLoopbackPage()
        let address = try await fixture.start()
        defer { fixture.listener.cancel() }
        try await withView { view in
            let url = try XCTUnwrap(URL(string: address))
            let foreign = try XCTUnwrap(URL(string: "about:blank"))
            let lease = try await IOSWorkflowNavigation.issue(on: view, authorize: {}, isLoading: { view.isLoading }) {
                let own = view.load(URLRequest(url: url))
                view.load(URLRequest(url: foreign))
                return own
            }
            let end = Date().addingTimeInterval(12)
            while lease.allowsWait(version: ConnectDocument.version(view), authorized: true), Date() < end {
                try await Task.sleep(nanoseconds: 50_000_000)
            }
            attach(lease, name: "Foreign callback after reservation")
            XCTAssertFalse(lease.allowsWait(version: ConnectDocument.version(view), authorized: true))
        }
    }

    @MainActor
    private func attach(_ lease: ConnectNavigationLease, name: String) {
        #if DEBUG
        let diagnostic = XCTAttachment(string: lease.debugState)
        diagnostic.name = name
        diagnostic.lifetime = .keepAlways
        add(diagnostic)
        #endif
    }
}
