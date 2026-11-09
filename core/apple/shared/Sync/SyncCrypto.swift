import CryptoKit
import Foundation
import Security

/// The sync channel's cryptography: P-256 ECDH, HKDF-SHA256 and AES-256-GCM, exactly as
/// fixed by `core/native/core-sync/tests/vectors/handshake-v1.json`.
enum SyncCrypto {
    struct Failure: Error {}

    enum Direction: String {
        case request = "req"
        case response = "res"
    }

    struct ChannelKeys {
        /// Seals initiator requests.
        let i2r: SymmetricKey
        /// Seals responder responses.
        let r2i: SymmetricKey
    }

    static func makePrivateKey() -> P256.KeyAgreement.PrivateKey { P256.KeyAgreement.PrivateKey() }

    /// The x9.63 uncompressed public key, base64url, as sent in `hello`.
    static func publicKeyText(_ key: P256.KeyAgreement.PrivateKey) -> String {
        Base64URL.encode(key.publicKey.x963Representation)
    }

    /// Parses and validates a peer key; an encoding that is not a point on P-256 throws.
    static func publicKey(_ text: String) throws -> P256.KeyAgreement.PublicKey {
        guard let data = Base64URL.decode(text), data.count == 65, data.first == 0x04 else { throw Failure() }
        return try P256.KeyAgreement.PublicKey(x963Representation: data)
    }

    static func sharedSecret(_ own: P256.KeyAgreement.PrivateKey, _ peer: P256.KeyAgreement.PublicKey) throws -> Data {
        try own.sharedSecretFromKeyAgreement(with: peer).withUnsafeBytes { Data($0) }
    }

    /// `HKDF-SHA256(ikm = Z, salt = T, info = "kelpie-sync-v1 i2r" | "… r2i", 32 bytes)`,
    /// where T is the 32-byte transcript hash the challenge encodes.
    static func channelKeys(sharedSecret: Data, challenge: String) throws -> ChannelKeys {
        guard let transcript = Base64URL.decode(challenge), transcript.count == 32 else { throw Failure() }
        let secret = SymmetricKey(data: sharedSecret)
        func derive(_ info: String) -> SymmetricKey {
            HKDF<SHA256>.deriveKey(inputKeyMaterial: secret, salt: transcript, info: Data(info.utf8), outputByteCount: 32)
        }
        return ChannelKeys(i2r: derive("kelpie-sync-v1 i2r"), r2i: derive("kelpie-sync-v1 r2i"))
    }

    /// 4 zero bytes followed by the 64-bit big-endian request sequence number.
    static func nonce(_ seq: UInt64) throws -> AES.GCM.Nonce {
        var bytes = [UInt8](repeating: 0, count: 4)
        withUnsafeBytes(of: seq.bigEndian) { bytes.append(contentsOf: $0) }
        return try AES.GCM.Nonce(data: bytes)
    }

    /// `kelpie-sync-v1\0<sessionId>\0<req|res>\0<seq in decimal>` as UTF-8.
    static func aad(sessionId: String, direction: Direction, seq: UInt64) -> Data {
        Data("kelpie-sync-v1\u{0}\(sessionId)\u{0}\(direction.rawValue)\u{0}\(seq)".utf8)
    }

    /// base64url(ciphertext || 16-byte tag).
    static func seal(_ plaintext: Data, key: SymmetricKey, sessionId: String, direction: Direction, seq: UInt64) throws -> String {
        let sealed = try AES.GCM.seal(
            plaintext, using: key, nonce: nonce(seq), authenticating: aad(sessionId: sessionId, direction: direction, seq: seq)
        )
        return Base64URL.encode(sealed.ciphertext + sealed.tag)
    }

    static func open(_ box: String, key: SymmetricKey, sessionId: String, direction: Direction, seq: UInt64) throws -> Data {
        guard let data = Base64URL.decode(box), data.count >= 16 else { throw Failure() }
        let sealed = try AES.GCM.SealedBox(nonce: nonce(seq), ciphertext: data.prefix(data.count - 16), tag: data.suffix(16))
        return try AES.GCM.open(sealed, using: key, authenticating: aad(sessionId: sessionId, direction: direction, seq: seq))
    }

    static func random(_ count: Int) -> Data {
        var bytes = [UInt8](repeating: 0, count: count)
        guard SecRandomCopyBytes(kSecRandomDefault, count, &bytes) == errSecSuccess else {
            preconditionFailure("The system random number generator failed")
        }
        return Data(bytes)
    }

    /// A fresh 16-byte replica id or 32-byte nonce, base64url.
    static func randomText(_ count: Int) -> String { Base64URL.encode(random(count)) }
}
