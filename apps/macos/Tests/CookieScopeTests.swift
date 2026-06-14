import XCTest
@testable import Kelpie

/// Deterministic unit tests for `CookieScope`'s pure matching logic.
/// No network, IO, or device dependency — all inputs are in-memory.
final class CookieScopeTests: XCTestCase {
    // MARK: - hostMatches

    func testHostMatchesExactHost() {
        XCTAssertTrue(CookieScope.hostMatches("example.com", cookieDomain: "example.com"))
    }

    func testHostMatchesIsCaseInsensitive() {
        XCTAssertTrue(CookieScope.hostMatches("Example.COM", cookieDomain: "example.com"))
    }

    func testHostMatchesDottedDomainMatchesSubdomain() {
        XCTAssertTrue(CookieScope.hostMatches("app.example.com", cookieDomain: ".example.com"))
    }

    func testHostMatchesDottedDomainMatchesApexHost() {
        // A leading-dot cookie domain is stripped, so the apex host matches exactly.
        XCTAssertTrue(CookieScope.hostMatches("example.com", cookieDomain: ".example.com"))
    }

    func testHostMatchesNonDottedDomainDoesNotMatchSubdomain() {
        // Without a leading dot the cookie is host-only: subdomains must not match.
        XCTAssertFalse(CookieScope.hostMatches("app.example.com", cookieDomain: "example.com"))
    }

    func testHostMatchesRejectsUnrelatedHost() {
        XCTAssertFalse(CookieScope.hostMatches("evil.com", cookieDomain: ".example.com"))
    }

    func testHostMatchesRejectsSuffixWithoutDotBoundary() {
        // "notexample.com" must not match ".example.com" — boundary requires a dot.
        XCTAssertFalse(CookieScope.hostMatches("notexample.com", cookieDomain: ".example.com"))
    }

    // MARK: - pathMatches

    func testPathMatchesExactPath() {
        XCTAssertTrue(CookieScope.pathMatches("/api", cookiePath: "/api"))
    }

    func testPathMatchesPrefixWithTrailingSlashCookiePath() {
        XCTAssertTrue(CookieScope.pathMatches("/api/users", cookiePath: "/api/"))
    }

    func testPathMatchesPrefixWithBoundarySlash() {
        // "/api" cookie path matches "/api/users" because the next char is "/".
        XCTAssertTrue(CookieScope.pathMatches("/api/users", cookiePath: "/api"))
    }

    func testPathMatchesRejectsPartialSegment() {
        // "/apixyz" must not match cookie path "/api" — not a path-segment boundary.
        XCTAssertFalse(CookieScope.pathMatches("/apixyz", cookiePath: "/api"))
    }

    func testPathMatchesEmptyCookiePathTreatedAsRoot() {
        XCTAssertTrue(CookieScope.pathMatches("/anything", cookiePath: ""))
    }

    // MARK: - domainMatches

    func testDomainMatchesExact() {
        XCTAssertTrue(CookieScope.domainMatches("example.com", filter: "example.com"))
    }

    func testDomainMatchesTolerantOfLeadingDotOnCookie() {
        XCTAssertTrue(CookieScope.domainMatches(".example.com", filter: "example.com"))
    }

    func testDomainMatchesTolerantOfLeadingDotOnFilter() {
        XCTAssertTrue(CookieScope.domainMatches("example.com", filter: ".example.com"))
    }

    func testDomainMatchesRejectsDifferentDomain() {
        XCTAssertFalse(CookieScope.domainMatches("example.com", filter: "other.com"))
    }

    // MARK: - scoped (integration of host + path + secure gating)

    private func makeCookie(
        name: String = "sid",
        domain: String,
        path: String = "/",
        secure: Bool = false
    ) -> HTTPCookie {
        var props: [HTTPCookiePropertyKey: Any] = [
            .name: name,
            .value: "v",
            .domain: domain,
            .path: path,
        ]
        if secure { props[.secure] = "TRUE" }
        return HTTPCookie(properties: props)!
    }

    func testScopedKeepsHostMatchingCookie() {
        let cookie = makeCookie(domain: ".example.com")
        let result = CookieScope.scoped([cookie], toURL: "https://app.example.com/")
        XCTAssertEqual(result.count, 1)
    }

    func testScopedDropsNonMatchingHost() {
        let cookie = makeCookie(domain: "example.com")
        let result = CookieScope.scoped([cookie], toURL: "https://other.com/")
        XCTAssertTrue(result.isEmpty)
    }

    func testScopedDropsCookieOutsidePath() {
        let cookie = makeCookie(domain: "example.com", path: "/admin")
        let result = CookieScope.scoped([cookie], toURL: "https://example.com/public")
        XCTAssertTrue(result.isEmpty)
    }

    func testScopedSecureCookieRequiresHTTPS() {
        let cookie = makeCookie(domain: "example.com", secure: true)
        let overHTTP = CookieScope.scoped([cookie], toURL: "http://example.com/")
        let overHTTPS = CookieScope.scoped([cookie], toURL: "https://example.com/")
        XCTAssertTrue(overHTTP.isEmpty, "Secure cookie must not be sent over http")
        XCTAssertEqual(overHTTPS.count, 1, "Secure cookie is sent over https")
    }

    func testScopedUnparseableURLYieldsEmpty() {
        let cookie = makeCookie(domain: "example.com")
        XCTAssertTrue(CookieScope.scoped([cookie], toURL: "not a url").isEmpty)
    }
}
