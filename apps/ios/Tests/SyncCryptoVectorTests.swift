import CryptoKit
import XCTest
@testable import KelpieBrowser

/// Reproduces every value in core/native/core-sync/tests/vectors/handshake-v1.json.
final class SyncCryptoVectorTests: XCTestCase {
    private func vectors() throws -> [String: Any] {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("core/native/core-sync/tests/vectors/handshake-v1.json")
        return try XCTUnwrap(SyncJSON.object(try Data(contentsOf: url)))
    }

    private func side(_ vectors: [String: Any], _ name: String) throws -> [String: String] {
        try XCTUnwrap(vectors[name] as? [String: String])
    }

    private func bytes(_ key: SymmetricKey) -> String { key.withUnsafeBytes { Base64URL.encode(Data($0)) } }

    func testKeysTranscriptSecretAndChannelKeys() throws {
        let vectors = try vectors()
        let initiator = try side(vectors, "initiator")
        let responder = try side(vectors, "responder")
        let initiatorKey = try P256.KeyAgreement.PrivateKey(rawRepresentation: XCTUnwrap(Base64URL.decode(XCTUnwrap(initiator["privateKey"]))))
        let responderKey = try P256.KeyAgreement.PrivateKey(rawRepresentation: XCTUnwrap(Base64URL.decode(XCTUnwrap(responder["privateKey"]))))
        XCTAssertEqual(SyncCrypto.publicKeyText(initiatorKey), initiator["key"])
        XCTAssertEqual(SyncCrypto.publicKeyText(responderKey), responder["key"])

        let challenge = try SyncStoreBridge.challenge(
            initiator: initiator.filter { $0.key != "privateKey" },
            responder: responder.filter { $0.key != "privateKey" }
        )
        XCTAssertEqual(challenge, vectors["challenge"] as? String)

        let fromInitiator = try SyncCrypto.sharedSecret(initiatorKey, SyncCrypto.publicKey(XCTUnwrap(responder["key"])))
        let fromResponder = try SyncCrypto.sharedSecret(responderKey, SyncCrypto.publicKey(XCTUnwrap(initiator["key"])))
        XCTAssertEqual(Base64URL.encode(fromInitiator), vectors["sharedSecret"] as? String)
        XCTAssertEqual(fromInitiator, fromResponder)

        let keys = try SyncCrypto.channelKeys(sharedSecret: fromInitiator, challenge: challenge)
        XCTAssertEqual(bytes(keys.i2r), vectors["i2r"] as? String)
        XCTAssertEqual(bytes(keys.r2i), vectors["r2i"] as? String)
    }

    func testEveryMessageNonceAADAndBox() throws {
        let vectors = try vectors()
        let sessionId = try XCTUnwrap(vectors["sessionId"] as? String)
        let i2r = SymmetricKey(data: try XCTUnwrap(Base64URL.decode(XCTUnwrap(vectors["i2r"] as? String))))
        let r2i = SymmetricKey(data: try XCTUnwrap(Base64URL.decode(XCTUnwrap(vectors["r2i"] as? String))))
        let messages = try XCTUnwrap(vectors["messages"] as? [[String: Any]])
        XCTAssertEqual(messages.count, 3)
        for message in messages {
            let direction = try XCTUnwrap(SyncCrypto.Direction(rawValue: XCTUnwrap(message["direction"] as? String)))
            let seq = try XCTUnwrap(SyncJSON.uint64(message["seq"]))
            let plaintext = Data(try XCTUnwrap(message["plaintext"] as? String).utf8)
            let key = direction == .request ? i2r : r2i
            XCTAssertEqual(try SyncCrypto.nonce(seq).withUnsafeBytes { Base64URL.encode(Data($0)) }, message["nonce"] as? String)
            XCTAssertEqual(Base64URL.encode(SyncCrypto.aad(sessionId: sessionId, direction: direction, seq: seq)), message["aad"] as? String)
            let box = try SyncCrypto.seal(plaintext, key: key, sessionId: sessionId, direction: direction, seq: seq)
            XCTAssertEqual(box, message["box"] as? String)
            XCTAssertEqual(try SyncCrypto.open(box, key: key, sessionId: sessionId, direction: direction, seq: seq), plaintext)
        }
    }

    func testTamperingWrongDirectionAndWrongSeqFail() throws {
        let key = SymmetricKey(size: .bits256)
        let box = try SyncCrypto.seal(Data("{}".utf8), key: key, sessionId: "s", direction: .request, seq: 4)
        XCTAssertThrowsError(try SyncCrypto.open(box, key: key, sessionId: "s", direction: .response, seq: 4))
        XCTAssertThrowsError(try SyncCrypto.open(box, key: key, sessionId: "s", direction: .request, seq: 5))
        XCTAssertThrowsError(try SyncCrypto.open(box, key: key, sessionId: "other", direction: .request, seq: 4))
        var tampered = try XCTUnwrap(Base64URL.decode(box))
        tampered[0] ^= 0x01
        XCTAssertThrowsError(try SyncCrypto.open(Base64URL.encode(tampered), key: key, sessionId: "s", direction: .request, seq: 4))
    }

    func testInvalidPublicKeysAreRejected() {
        XCTAssertThrowsError(try SyncCrypto.publicKey(Base64URL.encode(Data([0x04] + [UInt8](repeating: 0, count: 64)))))
        XCTAssertThrowsError(try SyncCrypto.publicKey(Base64URL.encode(Data([0x02] + [UInt8](repeating: 1, count: 32)))))
        XCTAssertThrowsError(try SyncCrypto.publicKey("not base64url!"))
    }

    func testBase64URLRoundTripAndStrictness() {
        let data = Data((0..<255).map { UInt8($0) })
        XCTAssertEqual(Base64URL.decode(Base64URL.encode(data)), data)
        XCTAssertFalse(Base64URL.encode(data).contains("="))
        XCTAssertNil(Base64URL.decode("ab+c"))
        XCTAssertNil(Base64URL.decode("a"))
    }
}
