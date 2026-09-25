import CryptoKit
import Foundation
import Security

struct UOAAuthorization {
    static let callback = "com.unlikeotherai.kelpie://oauth/callback"
    static let scopes = "openid profile settings.read settings.write"
    let state: String
    let verifier: String

    init() throws {
        state = try Self.randomValue()
        verifier = try Self.randomValue()
    }

    init(state: String, verifier: String) {
        self.state = state
        self.verifier = verifier
    }

    var challenge: String { Self.base64URL(Data(SHA256.hash(data: Data(verifier.utf8)))) }

    func url(clientID: String) throws -> URL {
        guard var components = URLComponents(string: UOATransport.origin + "/oauth/authorize") else {
            throw UOATransport.Failure(status: 400)
        }
        components.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: Self.callback),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "scope", value: Self.scopes),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256")
        ]
        guard let url = components.url else { throw UOATransport.Failure(status: 400) }
        return url
    }

    func code(from url: URL) throws -> String {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme == "com.unlikeotherai.kelpie", components.host == "oauth",
              components.path == "/callback", components.user == nil, components.password == nil,
              components.port == nil, components.fragment == nil else { throw UOATransport.Failure(status: 401) }
        let items = components.queryItems ?? []
        guard items.filter({ $0.name == "state" }).count == 1,
              items.first(where: { $0.name == "state" })?.value == state,
              items.filter({ $0.name == "code" }).count == 1,
              !items.contains(where: { $0.name == "error" }),
              let code = items.first(where: { $0.name == "code" })?.value, !code.isEmpty else {
            throw UOATransport.Failure(status: 401)
        }
        return code
    }

    private static func randomValue() throws -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            throw UOATransport.Failure(status: 0)
        }
        return base64URL(Data(bytes))
    }

    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
}
