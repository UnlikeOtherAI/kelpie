import UIKit
import WebKit
import XCTest
@testable import Kelpie

final class IOSWorkflowNavigationTests: XCTestCase {
    @MainActor
    func testRealWebKitHTTPNavigationUsesIssuedToken() async throws {
        try await navigate(priorBlank: false)
    }

    @MainActor
    func testRealWebKitHTTPNavigationAfterPriorBlankUsesIssuedToken() async throws {
        try await navigate(priorBlank: true)
    }

    @MainActor
    private func navigate(priorBlank: Bool) async throws {
        let fixture = try WorkflowLoopbackPage()
        let address = try await fixture.start()
        defer { fixture.listener.cancel() }
        let view = WKWebView(frame: CGRect(x: 0, y: 0, width: 390, height: 640))
        let container = UIView(frame: view.frame)
        let context = HandlerContext()
        let coordinator = TabWebViewContainer.Coordinator(
            browserState: BrowserState(),
            handlerContext: context,
            onScrollDirectionChange: { _ in },
            onWebViewReady: { _ in }
        )
        coordinator.install(webView: view, in: container)
        defer {
            view.stopLoading()
            ConnectDocument.reserve(view, lease: nil)
            withExtendedLifetime(coordinator) {}
        }
        if priorBlank { view.load(URLRequest(url: try XCTUnwrap(URL(string: "about:blank")))) }
        let url = try XCTUnwrap(URL(string: address))
        let lease = try await IOSWorkflowNavigation.issue(on: view, authorize: {}) {
            view.load(URLRequest(url: url))
        }
        let deadline = Date().addingTimeInterval(12)
        while lease.allowsWait(version: ConnectDocument.version(view), authorized: true),
              !lease.allowsRead(version: ConnectDocument.version(view), loading: view.isLoading, authorized: true),
              Date() < deadline {
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        #if DEBUG
        let diagnostic = XCTAttachment(string: lease.debugState)
        diagnostic.name = priorBlank ? "Real HTTP navigation after prior blank lease state" : "Real HTTP navigation lease state"
        diagnostic.lifetime = .keepAlways
        add(diagnostic)
        #endif
        XCTAssertTrue(lease.allowsWait(version: ConnectDocument.version(view), authorized: true))
        XCTAssertTrue(lease.allowsRead(version: ConnectDocument.version(view), loading: view.isLoading, authorized: true))
        XCTAssertEqual(view.title, "Count 0")
    }
}
