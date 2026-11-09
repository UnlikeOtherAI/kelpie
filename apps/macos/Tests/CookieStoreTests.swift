import WebKit
import XCTest
@testable import KelpieBrowser

/// Engine-neutral cookies, the one-writer default store and the renderer-switch copy.
@MainActor
final class CookieStoreTests: XCTestCase {
    private func cookie(_ name: String, domain: String, path: String = "/", value: String = "v",
                        expires: Date? = nil, secure: Bool = false, httpOnly: Bool = false) throws -> HTTPCookie {
        var properties: [HTTPCookiePropertyKey: Any] = [.name: name, .value: value, .domain: domain, .path: path]
        if let expires { properties[.expires] = expires }
        if secure { properties[.secure] = "TRUE" }
        if httpOnly { properties[HTTPCookiePropertyKey("HttpOnly")] = "TRUE" }
        return try XCTUnwrap(HTTPCookie(properties: properties))
    }

    func testWebKitSameSiteMapsToTheFourWireNames() throws {
        let absent = BrowserCookie(try cookie("a", domain: "example.test"))
        XCTAssertEqual(absent.sameSite, .unspecified)
        var lax = try cookie("b", domain: "example.test").properties ?? [:]
        lax[.sameSitePolicy] = HTTPCookieStringPolicy.sameSiteLax.rawValue
        XCTAssertEqual(BrowserCookie(try XCTUnwrap(HTTPCookie(properties: lax))).sameSite, .lax)
        let none = BrowserCookie(name: "c", value: "1", domain: ".example.test", path: "/", expires: nil,
                                 secure: true, httpOnly: false, sameSite: .noRestriction)
        XCTAssertEqual(none.syncWireJSON?["sameSite"] as? String, "None")
        XCTAssertEqual(none.bridgeDictionary?["sameSite"] as? String, "None")
        var insecure = none
        insecure.secure = false
        XCTAssertEqual(insecure.bridgeDictionary?["sameSite"] as? String, "Unspecified",
                       "Chromium refuses SameSite=None without Secure")
    }

    func testWireShapeUsesWholeSecondsAndNullForSessionCookies() throws {
        // Foundation clamps far expiries, so the fixture stays within a year.
        let expiry = floor(Date().timeIntervalSince1970) + 86_400.9
        let expiring = BrowserCookie(try cookie("a", domain: ".example.test", expires: Date(timeIntervalSince1970: expiry)))
        XCTAssertEqual(expiring.syncWireJSON?["expires"] as? Int64, Int64(floor(expiry)))
        let session = BrowserCookie(try cookie("b", domain: "example.test"))
        XCTAssertTrue(session.syncWireJSON?["expires"] is NSNull)
        XCTAssertNil(BrowserCookie(name: "c", value: "", domain: "example.test", path: "/", expires: nil,
                                   secure: false, httpOnly: false, sameSite: nil).syncWireJSON,
                     "A cookie whose SameSite the engine cannot name is never described")
    }

    func testRendererSwitchCopyKeepsHttpOnlyAndSessionCookiesAndTheTargetsOwn() async throws {
        let sourceData = WKWebsiteDataStore.nonPersistent()
        let targetData = WKWebsiteDataStore.nonPersistent()
        let source = sourceData.httpCookieStore
        let target = targetData.httpCookieStore
        await source.setCookie(try cookie("session", domain: ".example.test", secure: true, httpOnly: true))
        await source.setCookie(try cookie("pref", domain: "example.test", expires: Date(timeIntervalSinceNow: 86_400)))
        await target.setCookie(try cookie("chromiumOnly", domain: ".example.test"))
        await target.setCookie(try cookie("pref", domain: "example.test", value: "stale"))

        let report = await CookieCopier.copyAll(from: .webKit(source), to: .webKit(target))

        XCTAssertEqual(report.copied, 2)
        XCTAssertTrue(report.failed.isEmpty)
        let copied = Dictionary(uniqueKeysWithValues: await target.allCookies().map { ($0.name, $0) })
        XCTAssertEqual(Set(copied.keys), ["session", "pref", "chromiumOnly"], "A switch never deletes")
        XCTAssertEqual(copied["pref"]?.value, "v", "The outgoing engine's value wins")
        XCTAssertEqual(copied["session"]?.isHTTPOnly, true)
        XCTAssertEqual(copied["session"]?.isSecure, true)
        XCTAssertNil(copied["session"]?.expiresDate, "A session cookie stays a session cookie")
        XCTAssertEqual(copied["pref"]?.domain, "example.test", "Host-only stays host-only")
        withExtendedLifetime((sourceData, targetData)) {}
    }

    func testRendererSwitchWithAnUnreadableSourceChangesNothing() async throws {
        let targetData = WKWebsiteDataStore.nonPersistent()
        let target = targetData.httpCookieStore
        await target.setCookie(try cookie("kept", domain: "example.test"))
        #if !KELPIE_WEBKIT_ONLY
        // Chromium is not initialized in the test host, so its store cannot be read.
        let report = await CookieCopier.copyAll(from: .chromium, to: .webKit(target))
        XCTAssertTrue(report.sourceUnreadable)
        #endif
        let names = await target.allCookies().map(\.name)
        XCTAssertEqual(names, ["kept"])
        withExtendedLifetime(targetData) {}
    }

    func testNoPeriodicCookieWriterRemains() {
        let context = HandlerContext()
        func timerProperties(_ subject: Any) -> [String] {
            Mirror(reflecting: subject).children
                .filter { String(describing: type(of: $0.value)).contains("Timer") }
                .compactMap(\.label)
        }
        XCTAssertEqual(timerProperties(context), [], "The 2 s shared-jar poller is retired")
        XCTAssertEqual(timerProperties(context.defaultCookies), [])
    }

    func testDefaultStoreRunsOneOperationAtATime() async {
        final class Log { var entries: [String] = [] }
        let store = DefaultCookieStore(engine: .webkit)
        let log = Log()
        let slow = Task { @MainActor in
            await store.exclusive { _ in
                log.entries.append("slow-start")
                try? await Task.sleep(nanoseconds: 50_000_000)
                log.entries.append("slow-end")
            }
        }
        await Task.yield()
        await store.exclusive { _ in log.entries.append("fast") }
        await slow.value
        XCTAssertEqual(log.entries, ["slow-start", "slow-end", "fast"])
    }
}
