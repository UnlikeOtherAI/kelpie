import AppKit
import WebKit
import XCTest
@testable import KelpieBrowser

@MainActor
final class UOALoginStorageTests: XCTestCase {
    func testNativeLoginWindowSharesSessionCookiesWithNormalTabsAfterClosing() async throws {
        var results: [UOALoginResult] = []
        let previousWindows = Set(NSApp.windows.map(ObjectIdentifier.init))
        let surface = UOALoginWindowController.present(try XCTUnwrap(URL(string: "about:blank"))) { results.append($0) }
        defer { surface.close() }
        let window = try XCTUnwrap(NSApp.windows.first { !previousWindows.contains(ObjectIdentifier($0)) })
        let login = try XCTUnwrap(window.contentView?.subviews.compactMap { $0 as? WKWebView }.first)
        XCTAssertTrue(login.configuration.websiteDataStore === KelpieWebsiteData.store)
        let cookie = try XCTUnwrap(HTTPCookie(properties: [
            .name: "kelpie-login-\(UUID().uuidString)", .value: "fixture-session", .domain: "kelpie-login-fixture.invalid", .path: "/",
            .secure: "TRUE", HTTPCookiePropertyKey("HttpOnly"): "TRUE"
        ]))
        let cookieStore = login.configuration.websiteDataStore.httpCookieStore
        await cookieStore.setCookie(cookie)
        surface.close()
        XCTAssertTrue(results.isEmpty, "Programmatic dismissal cannot report a late login result")
        let ordinary = WKWebViewRenderer()
        let isolated = WKWebViewRenderer(dataStore: .nonPersistent())
        let normalCookies = await ordinary.websiteDataStore.httpCookieStore.allCookies()
        let isolatedCookies = await isolated.websiteDataStore.httpCookieStore.allCookies()
        await cookieStore.deleteCookie(cookie)
        ordinary.invalidate()
        isolated.invalidate()
        XCTAssertEqual(normalCookies.first { $0.name == cookie.name }?.value, "fixture-session")
        XCTAssertNil(isolatedCookies.first { $0.name == cookie.name })
    }

    func testClosingNativeLoginReportsCancellationOnceAndAllowsAnotherAttempt() throws {
        for _ in 0..<3 {
            var results: [UOALoginResult] = []
            let previousWindows = Set(NSApp.windows.map(ObjectIdentifier.init))
            let surface = UOALoginWindowController.present(try XCTUnwrap(URL(string: "about:blank"))) { results.append($0) }
            let window = try XCTUnwrap(NSApp.windows.first { !previousWindows.contains(ObjectIdentifier($0)) })
            window.performClose(nil)
            surface.close()
            XCTAssertEqual(results, [.cancelled])
        }
    }
}
