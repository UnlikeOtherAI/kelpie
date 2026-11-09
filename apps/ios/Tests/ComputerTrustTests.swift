import XCTest
import CryptoKit
@testable import KelpieBrowser

final class ComputerTrustTests: XCTestCase {
    private var directory: URL!
    private var store: PairingStore!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        store = PairingStore(storeURL: directory.appendingPathComponent("pairings.json"))
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: directory)
    }

    private func start(_ privateKey: Curve25519.Signing.PrivateKey, source: String) throws -> String {
        let key = privateKey.publicKey.rawRepresentation.map { String(format: "%02x", $0) }.joined()
        var body: [String: Any] = ["clientId": UUID().uuidString, "clientName": "Test computer", "computerPublicKey": key]
        let challenge = store.trustedComputers.start(body: body, source: source)
        XCTAssertEqual(challenge.status, 202)
        let id = try XCTUnwrap(challenge.json["requestId"] as? String)
        let bytes = Data("kelpie-computer-pair-v1\n\(id)\n\(key)".utf8)
        body["requestId"] = id
        body["computerSignature"] = try privateKey.signature(for: bytes).map { String(format: "%02x", $0) }.joined()
        XCTAssertEqual(store.trustedComputers.start(body: body, source: source).status, 202)
        return id
    }

    func testComputerTrustFollowsSignatureAcrossIPChangesAndRestart() throws {
        let key = Curve25519.Signing.PrivateKey()
        let id = try start(key, source: "192.0.2.1")
        XCTAssertNotNil(store.trustedComputers.pending())
        XCTAssertTrue(store.trustedComputers.approve(requestId: id))
        let token = try XCTUnwrap(store.trustedComputers.status(requestId: id, source: "192.0.2.1")["token"] as? String)
        store = PairingStore(storeURL: directory.appendingPathComponent("pairings.json"))
        XCTAssertNotNil(store.trustedComputers.clientId(for: "203.0.113.2", token: token))
        let moved = try start(key, source: "203.0.113.2")
        XCTAssertNil(store.trustedComputers.pending())
        XCTAssertEqual(store.trustedComputers.status(requestId: moved, source: "203.0.113.2")["status"] as? String, "approved")
        XCTAssertNil(store.trustedComputers.clientId(for: "192.0.2.1"))
        let stranger = try start(Curve25519.Signing.PrivateKey(), source: "192.0.2.1")
        XCTAssertEqual(store.trustedComputers.pending()?.requestId, stranger)
        let computer = try XCTUnwrap(store.trustedComputers.list().first)
        XCTAssertTrue(store.trustedComputers.revoke(publicKey: computer.publicKey))
        XCTAssertNil(store.trustedComputers.clientId(for: "203.0.113.2", token: token))
    }

    func testLocalhostProgramsAreAllowedButPagesCannotInheritPermission() {
        let middleware = AuthMiddleware(store: store)
        func request(_ headers: [String: [String]]) -> ParsedHTTPRequest {
            ParsedHTTPRequest(method: "POST", path: "/v1/browser-control", query: "", headers: headers,
                              body: Data("{}".utf8), sourceAddress: "127.0.0.1", hasTransferEncoding: false)
        }
        let headers = ["host": ["127.0.0.1:8420"], "content-type": ["application/json"]]
        guard case .authenticated = middleware.evaluate(request(headers)) else { return XCTFail("Local program must be allowed") }
        guard case .reject(403, _, _) = middleware.evaluate(request(headers.merging(["origin": ["null"]]) { $1 })) else {
            return XCTFail("Webpage must not inherit localhost permission")
        }
    }
}
