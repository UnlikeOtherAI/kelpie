import Combine
import AuthenticationServices

/// UOA is the identity authority. Tokens, profile and avatar live only in memory.
@MainActor
final class UOAAccount: NSObject, ObservableObject, ASWebAuthenticationPresentationContextProviding {
    static let shared = UOAAccount()

    struct Profile: Decodable {
        let sub: String
        let email: String
        let name: String?
    }

    @Published private(set) var profile: Profile?
    @Published private(set) var avatar: UOAAvatar?
    @Published private(set) var signingIn = false
    @Published var error: String?
    private let transport = UOATransport()
    private var session: ASWebAuthenticationSession?
    private var expiryTask: Task<Void, Never>?
    private var generation = UUID()
    private var accessToken: String?
    private var expiresAt = Date.distantPast

    func signIn() {
        guard !signingIn else { return }
        signingIn = true
        error = nil
        let attempt = UUID()
        generation = attempt
        Task { [weak self] in
            guard let self else { return }
            do {
                let clientID = try await registeredClient()
                let authorization = try UOAAuthorization()
                let url = try authorization.url(clientID: clientID)
                guard generation == attempt else { return }
                let authSession = ASWebAuthenticationSession(url: url, callbackURLScheme: "com.unlikeotherai.kelpie") { [weak self] callback, failure in
                    Task { @MainActor in
                        guard let self, self.generation == attempt else { return }
                        self.session = nil
                        if let callback {
                            await self.complete(callback, authorization: authorization, clientID: clientID, attempt: attempt)
                        } else {
                            self.signingIn = false
                            if (failure as? ASWebAuthenticationSessionError)?.code != .canceledLogin {
                                self.error = "Sign-in could not be opened. Please try again."
                            }
                        }
                    }
                }
                authSession.presentationContextProvider = self
                authSession.prefersEphemeralWebBrowserSession = false
                session = authSession
                if !authSession.start() { throw UOATransport.Failure(status: 0) }
            } catch {
                guard generation == attempt else { return }
                signingIn = false
                self.error = error.localizedDescription
            }
        }
    }

    func signOut() {
        generation = UUID()
        session?.cancel()
        session = nil
        expiryTask?.cancel()
        accessToken = nil
        expiresAt = .distantPast
        profile = nil
        avatar = nil
        signingIn = false
        error = nil
        BookmarkStore.shared.useLocalBookmarks()
    }

    func cancelSignIn() { signOut() }

    func request(_ path: String, method: String = "GET", body: Data? = nil, version: String? = nil) async throws -> UOATransport.Response {
        guard let token = accessToken, expiresAt > Date() else { throw UOATransport.Failure(status: 401) }
        let current = generation
        do {
            let response = try await transport.request(path, method: method, token: token, body: body, version: version)
            guard current == generation else { throw CancellationError() }
            return response
        } catch {
            if current == generation, (error as? UOATransport.Failure)?.status == 401 {
                signOut()
                self.error = error.localizedDescription
            }
            throw error
        }
    }

    private func registeredClient() async throws -> String {
        let body = try JSONSerialization.data(withJSONObject: [
            "client_name": UOAPresentation.clientName, "redirect_uris": [UOAAuthorization.callback],
            "token_endpoint_auth_method": "none", "scope": UOAAuthorization.scopes
        ])
        let response = try await transport.request("/oauth/register", method: "POST", body: body)
        struct Registration: Decodable { let client_id: String }
        let clientID = try JSONDecoder().decode(Registration.self, from: response.data).client_id
        return clientID
    }

    private func complete(_ callback: URL, authorization: UOAAuthorization, clientID: String, attempt: UUID) async {
        do {
            let code = try authorization.code(from: callback)
            let body = try JSONSerialization.data(withJSONObject: [
                "grant_type": "authorization_code", "code": code, "client_id": clientID,
                "redirect_uri": UOAAuthorization.callback, "code_verifier": authorization.verifier
            ])
            let response = try await transport.request("/oauth/token", method: "POST", body: body)
            struct Token: Decodable { let access_token: String; let expires_in: Double }
            let token = try JSONDecoder().decode(Token.self, from: response.data)
            guard generation == attempt else { return }
            accessToken = token.access_token
            expiresAt = Date().addingTimeInterval(token.expires_in)
            let identity = try await request("/oauth/me")
            let user = try JSONDecoder().decode(Profile.self, from: identity.data)
            guard generation == attempt else { return }
            profile = user
            signingIn = false
            BookmarkStore.shared.useAccount(self)
            expiryTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(max(0, token.expires_in)))
                guard !Task.isCancelled, let self, self.generation == attempt else { return }
                self.signOut()
                self.error = "Your UOA session has expired. Sign in again."
            }
            if let picture = try? await request("/oauth/me/avatar"), generation == attempt {
                avatar = UOAAvatar(data: picture.data)
            }
        } catch {
            guard generation == attempt else { return }
            signOut()
            self.error = error.localizedDescription
        }
    }

    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated { UOAPresentation.anchor }
    }
}
