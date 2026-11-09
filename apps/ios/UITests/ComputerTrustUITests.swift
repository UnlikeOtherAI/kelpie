import CryptoKit
import XCTest

final class ComputerTrustUITests: XCTestCase {
    private let port = 18430

    @MainActor
    func testApproveReconnectAndRevokeComputerThroughSettings() async throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = [
            "--port", String(port), "-hideWelcomeCard", "YES", "-sessionTabURLs", "()", "-homeURL", "about:blank"
        ]
        app.launch()
        let more = app.buttons["browser.more"]
        XCTAssertTrue(more.waitForExistence(timeout: 15))
        let key = Curve25519.Signing.PrivateKey()
        let first = try await prove(key)
        XCTAssertEqual(first["approvalRequired"] as? Bool, true)
        let allow = app.buttons["Allow computer"]
        XCTAssertTrue(allow.waitForExistence(timeout: 5))
        capture(app, "computer-approval")
        allow.tap()
        let status = try await request("/v1/pair/status?requestId=\(first["requestId"] as? String ?? "")")
        XCTAssertEqual(status["status"] as? String, "approved")
        let reconnect = try await prove(key)
        XCTAssertEqual(reconnect["approvalRequired"] as? Bool, false)
        XCTAssertFalse(allow.exists)
        more.tap()
        app.buttons["Settings"].tap()
        let clients = app.buttons["Paired Clients"]
        if !clients.exists { app.swipeUp() }
        XCTAssertTrue(clients.waitForExistence(timeout: 5))
        clients.tap()
        XCTAssertTrue(app.staticTexts["Trusted computers"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["UI test computer"].exists)
        capture(app, "trusted-computers")
        app.buttons["Revoke"].firstMatch.tap()
        XCTAssertFalse(app.staticTexts["UI test computer"].exists)
        app.buttons["Done"].tap()
        app.swipeDown()
        let revoked = try await prove(key)
        XCTAssertEqual(revoked["approvalRequired"] as? Bool, true)
        XCTAssertTrue(allow.waitForExistence(timeout: 5))
        app.buttons["No"].tap()
    }

    private func prove(_ key: Curve25519.Signing.PrivateKey) async throws -> [String: Any] {
        let publicKey = key.publicKey.rawRepresentation.map { String(format: "%02x", $0) }.joined()
        var body: [String: Any] = [
            "clientId": UUID().uuidString, "clientName": "UI test computer", "computerPublicKey": publicKey
        ]
        let challenge = try await request("/v1/pair", body: body)
        let id = try XCTUnwrap(challenge["requestId"] as? String)
        body["requestId"] = id
        body["computerSignature"] = try key.signature(for: Data("kelpie-computer-pair-v1\n\(id)\n\(publicKey)".utf8))
            .map { String(format: "%02x", $0) }.joined()
        return try await request("/v1/pair", body: body)
    }

    private func request(_ path: String, body: [String: Any]? = nil) async throws -> [String: Any] {
        var request = URLRequest(url: try XCTUnwrap(URL(string: "http://127.0.0.1:\(port)\(path)")))
        request.timeoutInterval = 10
        if let body {
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        XCTAssertTrue((200...299).contains((response as? HTTPURLResponse)?.statusCode ?? 0))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    @MainActor
    private func capture(_ app: XCUIApplication, _ name: String) {
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = name
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
}
