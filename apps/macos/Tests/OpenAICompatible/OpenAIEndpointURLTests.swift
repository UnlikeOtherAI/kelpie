import XCTest
@testable import Kelpie

final class OpenAIEndpointURLTests: XCTestCase {
    private func normalized(_ raw: String) throws -> String {
        try OpenAIEndpointURL.normalize(raw).string
    }

    func testPreservesBasePathsAndStripsTrailingSlashes() throws {
        XCTAssertEqual(try normalized("http://127.0.0.1:18880/v1"), "http://127.0.0.1:18880/v1")
        XCTAssertEqual(try normalized("http://127.0.0.1:18880/v1/"), "http://127.0.0.1:18880/v1")
        XCTAssertEqual(try normalized("  https://Example.COM/openai/v1///  "), "https://example.com/openai/v1")
        XCTAssertEqual(try normalized("http://host:9000/api//openai//v1"), "http://host:9000/api/openai/v1")
    }

    func testDefaultsEmptyPathToV1() throws {
        XCTAssertEqual(try normalized("http://studio.local:1234"), "http://studio.local:1234/v1")
        XCTAssertEqual(try normalized("http://localhost:8080/"), "http://localhost:8080/v1")
    }

    func testStripsPastedOperationSuffixesWithoutDuplicatingV1() throws {
        XCTAssertEqual(try normalized("http://h:8080/v1/chat/completions"), "http://h:8080/v1")
        XCTAssertEqual(try normalized("http://h:8080/v1/models/"), "http://h:8080/v1")
        XCTAssertEqual(try normalized("https://h/openai/v1/completions"), "https://h/openai/v1")
    }

    func testJoinsOperationsWithoutDoubleSlashesOrDuplicateV1() throws {
        let base = try OpenAIEndpointURL.normalize("http://127.0.0.1:18880/v1/")
        XCTAssertEqual(base.url(for: "models").absoluteString, "http://127.0.0.1:18880/v1/models")
        XCTAssertEqual(base.url(for: "/chat/completions").absoluteString, "http://127.0.0.1:18880/v1/chat/completions")
        let nested = try OpenAIEndpointURL.normalize("https://gw.example/openai/v1")
        XCTAssertEqual(nested.url(for: "chat/completions").absoluteString, "https://gw.example/openai/v1/chat/completions")
    }

    func testSupportsLiteralIPsIPv6AndMDNSNames() throws {
        XCTAssertEqual(try normalized("http://192.168.1.197:8080/v1"), "http://192.168.1.197:8080/v1")
        XCTAssertEqual(try normalized("http://[::1]:8080/v1"), "http://[::1]:8080/v1")
        XCTAssertEqual(try normalized("http://maxis.local:8080/v1"), "http://maxis.local:8080/v1")
    }

    func testPortRange() throws {
        XCTAssertEqual(try OpenAIEndpointURL.normalize("http://h:1/v1").port, 1)
        XCTAssertEqual(try OpenAIEndpointURL.normalize("http://h:65535/v1").port, 65_535)
        XCTAssertNil(try OpenAIEndpointURL.normalize("https://h/v1").port)
        for bad in ["http://h:0/v1", "http://h:65536/v1", "http://h:99999/v1", "http://h:/v1", "http://h:abc/v1", "http://[::1]:70000/v1"] {
            XCTAssertThrowsError(try OpenAIEndpointURL.normalize(bad), bad) { error in
                XCTAssertTrue([.invalidPort, .malformed].contains(error as? OpenAIEndpointURL.ValidationError), bad)
            }
        }
    }

    func testRejectsUnsafeOrUnsupportedInput() {
        let cases: [(String, OpenAIEndpointURL.ValidationError)] = [
            ("", .empty),
            ("ftp://h/v1", .unsupportedScheme),
            ("127.0.0.1:8080/v1", .unsupportedScheme),
            ("http://user:secret@h:8080/v1", .userInfoNotAllowed),
            ("http://h:8080/v1?key=abc", .queryNotAllowed),
            ("http://h:8080/v1#frag", .queryNotAllowed)
        ]
        for (raw, expected) in cases {
            XCTAssertThrowsError(try OpenAIEndpointURL.normalize(raw), raw) { error in
                XCTAssertEqual(error as? OpenAIEndpointURL.ValidationError, expected, raw)
            }
        }
    }

    func testLoopbackDetection() throws {
        XCTAssertTrue(try OpenAIEndpointURL.normalize("http://localhost:1/v1").isLoopback)
        XCTAssertTrue(try OpenAIEndpointURL.normalize("http://127.0.0.1:1/v1").isLoopback)
        XCTAssertTrue(try OpenAIEndpointURL.normalize("http://[::1]:1/v1").isLoopback)
        XCTAssertFalse(try OpenAIEndpointURL.normalize("http://maxis.local:1/v1").isLoopback)
        XCTAssertFalse(try OpenAIEndpointURL.normalize("http://192.168.1.2:1/v1").isLoopback)
    }

    func testRedirectPolicyIsSameOriginOnly() throws {
        func url(_ text: String) -> URL? { URL(string: text) }
        XCTAssertTrue(URLSessionOpenAITransport.shouldFollowRedirect(from: url("http://h:8080/v1/models"), to: url("http://h:8080/v1/models/")))
        XCTAssertTrue(URLSessionOpenAITransport.shouldFollowRedirect(from: url("https://h/v1/models"), to: url("https://h:443/x")))
        XCTAssertFalse(URLSessionOpenAITransport.shouldFollowRedirect(from: url("http://h:8080/v1"), to: url("http://evil:8080/v1")))
        XCTAssertFalse(URLSessionOpenAITransport.shouldFollowRedirect(from: url("http://h:8080/v1"), to: url("http://h:9090/v1")))
        XCTAssertFalse(URLSessionOpenAITransport.shouldFollowRedirect(from: url("https://h/v1"), to: url("http://h/v1")))
    }
}
