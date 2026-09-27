import Foundation

/// The only UOA material Kelpie keeps across launches: the public client id and the rotating
/// refresh token UOA issued to it. Profile, avatar and access tokens stay in memory.
struct UOAStoredSession: Codable, Equatable {
    let clientID: String
    let refreshToken: String

    enum CodingKeys: String, CodingKey {
        case clientID = "client_id"
        case refreshToken = "refresh_token"
    }
}

protocol UOASessionStorage: AnyObject {
    func load() -> UOAStoredSession?
    func save(_ session: UOAStoredSession)
    func clear()
}

/// Encrypted file storage through `SecretStore` — never the Keychain.
final class UOASecretSessionStorage: UOASessionStorage {
    static let key = "uoa.session.v1"

    func load() -> UOAStoredSession? {
        guard let raw = SecretStore.shared.get(Self.key),
              let session = try? JSONDecoder().decode(UOAStoredSession.self, from: Data(raw.utf8)),
              !session.clientID.isEmpty, !session.refreshToken.isEmpty else { return nil }
        return session
    }

    func save(_ session: UOAStoredSession) {
        guard let data = try? JSONEncoder().encode(session), let raw = String(data: data, encoding: .utf8) else { return }
        SecretStore.shared.set(Self.key, value: raw)
    }

    func clear() { SecretStore.shared.remove(Self.key) }
}

/// A successful `/oauth/token` response from either the code or the refresh grant.
struct UOATokenGrant {
    let accessToken: String
    let expiresIn: TimeInterval
    /// Absent from UOA servers that do not issue refresh tokens; the session is then memory-only.
    let refreshToken: String?

    init(data: Data) throws {
        struct Body: Decodable {
            let access_token: String
            let expires_in: Double
            let refresh_token: String?
        }
        guard let body = try? JSONDecoder().decode(Body.self, from: data), !body.access_token.isEmpty,
              body.expires_in.isFinite, body.expires_in > 0 else { throw UOATransport.Failure(status: 0) }
        accessToken = body.access_token
        expiresIn = body.expires_in
        refreshToken = body.refresh_token?.isEmpty == false ? body.refresh_token : nil
    }
}

extension UOATransport.Failure {
    /// UOA refused the credential itself, as opposed to the request failing in transit.
    var rejectsCredential: Bool { [400, 401, 403].contains(status) }
}
