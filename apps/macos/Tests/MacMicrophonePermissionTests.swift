import Foundation
import XCTest
@testable import KelpieBrowser

@MainActor
final class MacMicrophonePermissionTests: XCTestCase {
    func testOriginKeepsSchemeHostAndNondefaultPort() {
        XCTAssertEqual(
            MacMicrophonePermission.origin(for: URL(string: "https://Voice.Example:8999/session?mode=voice")),
            "https://voice.example:8999"
        )
        XCTAssertEqual(
            MacMicrophonePermission.origin(scheme: "https", host: "voice.example", port: 443),
            "https://voice.example"
        )
        XCTAssertEqual(
            MacMicrophonePermission.origin(scheme: "https", host: "voice.example", port: 0),
            "https://voice.example"
        )
    }

    func testOnlySecureOriginsOrLoopbackCanBeAllowed() {
        XCTAssertNil(MacMicrophonePermission.origin(for: URL(string: "http://voice.example")))
        XCTAssertNil(MacMicrophonePermission.origin(for: URL(string: "file:///voice.html")))
        XCTAssertEqual(MacMicrophonePermission.origin(for: URL(string: "http://localhost:8999")), "http://localhost:8999")
        XCTAssertEqual(MacMicrophonePermission.origin(for: URL(string: "http://[::1]:8999")), "http://[::1]:8999")
    }
}
