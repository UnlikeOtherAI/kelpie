import Foundation
import Combine
import AuthenticationServices

/// UOA is the identity authority. Profile, avatar and access tokens live only in memory; the only
/// persisted material is UOA's rotating refresh token and the client id it is bound to.
@MainActor
final class UOAAccount: NSObject, ObservableObject, ASWebAuthenticationPresentationContextProviding {
    static let shared = UOAAccount()
    typealias Transport = (_ path: String, _ method: String, _ token: String?, _ body: Data?, _ version: String?) async throws -> UOATransport.Response

    struct Profile: Decodable {
        let sub: String
        let email: String
        let name: String?
    }

    /// UOA refused the stored refresh token, which has already been forgotten.
    struct SessionRejected: Error {}

    @Published private(set) var profile: Profile?
    @Published private(set) var avatar: UOAAvatar?
    @Published private(set) var signingIn = false
    @Published var error: String?
    private let transport: Transport
    private let storage: UOASessionStorage
    private let bookmarks: BookmarkStore
    private var session: ASWebAuthenticationSession?
    private var expiryTask: Task<Void, Never>?
    private var refreshTask: Task<String, Error>?
    private var generation = UUID()
    private var credential: UOAStoredSession?
    private var accessToken: String?
    private var expiresAt = Date.distantPast

    init(transport: Transport? = nil, storage: UOASessionStorage = UOASecretSessionStorage(), bookmarks: BookmarkStore? = nil) {
        let client = UOATransport()
        self.transport = transport ?? { try await client.request($0, method: $1, token: $2, body: $3, version: $4) }
        self.storage = storage
        self.bookmarks = bookmarks ?? .shared
        super.init()
    }

    /// Restores the persisted session at launch. Never opens the browser.
    func restoreSession() {
        guard profile == nil, !signingIn, let stored = storage.load() else { return }
        let attempt = beginAttempt()
        Task { _ = await resume(stored, attempt: attempt, fallback: false) }
    }

    func signIn() {
        guard profile == nil, !signingIn else { return }
        let attempt = beginAttempt()
        Task {
            if let stored = storage.load() {
                guard await resume(stored, attempt: attempt, fallback: true) else { return }
            }
            await authorize(attempt)
        }
    }

    func signOut() {
        let issued = credential ?? storage.load()
        reset(clearStorage: true)
        if let issued { revoke(issued) }
    }

    func cancelSignIn() { signOut() }

    func request(_ path: String, method: String = "GET", body: Data? = nil, version: String? = nil) async throws -> UOATransport.Response {
        let current = generation
        guard accessToken != nil || credential != nil else { throw UOATransport.Failure(status: 401) }
        do {
            let token = try await validAccessToken(current)
            do {
                return try await send(path, method: method, token: token, body: body, version: version, current: current)
            } catch let failure as UOATransport.Failure where failure.status == 401 && credential != nil {
                // UOA refused the access token early; rotate once and retry this request.
                let renewed = try await refreshAccessToken(current, replacing: token)
                return try await send(path, method: method, token: renewed, body: body, version: version, current: current)
            }
        } catch is SessionRejected {
            if current == generation { expire() }
            throw UOATransport.Failure(status: 401)
        } catch let failure as UOATransport.Failure where failure.status == 401 {
            if current == generation { expire() }
            throw failure
        }
    }

    // MARK: - Session lifecycle

    private func beginAttempt() -> UUID {
        let attempt = UUID()
        generation = attempt
        signingIn = true
        error = nil
        return attempt
    }

    /// Resumes a stored session. Returns true only when UOA rejected it and interactive sign-in should follow.
    private func resume(_ stored: UOAStoredSession, attempt: UUID, fallback: Bool) async -> Bool {
        guard generation == attempt else { return false }
        credential = stored
        do {
            _ = try await refreshAccessToken(attempt)
            try await finishSignIn(attempt)
            return false
        } catch is SessionRejected {
            guard generation == attempt else { return false }
            if fallback { return true }
            expire()
            return false
        } catch {
            guard generation == attempt else { return false }
            // A failure in transit keeps the stored session for the next sign-in or launch.
            reset(clearStorage: false)
            self.error = "Could not restore your UOA sign-in. Please try again."
            return false
        }
    }

    /// Loads the UOA profile and switches favourites once a valid access token exists.
    private func finishSignIn(_ attempt: UUID) async throws {
        let identity = try await request("/oauth/me")
        let user = try JSONDecoder().decode(Profile.self, from: identity.data)
        guard generation == attempt else { throw CancellationError() }
        profile = user
        signingIn = false
        bookmarks.useAccount(self)
        if let picture = try? await request("/oauth/me/avatar"), generation == attempt {
            avatar = UOAAvatar(data: picture.data)
        }
    }

    /// Stores what a token response issued. The rotated refresh token is persisted before the access token is used.
    private func accept(_ grant: UOATokenGrant, clientID: String) {
        if let refreshToken = grant.refreshToken {
            let stored = UOAStoredSession(clientID: clientID, refreshToken: refreshToken)
            storage.save(stored)
            credential = stored
        } else {
            forgetCredential()
        }
        accessToken = grant.accessToken
        expiresAt = Date().addingTimeInterval(grant.expiresIn)
        scheduleExpiry()
    }

    /// Only memory-only sessions (no refresh token issued) end when the access token expires.
    private func scheduleExpiry() {
        expiryTask?.cancel()
        expiryTask = nil
        guard credential == nil else { return }
        let current = generation
        let delay = max(0, expiresAt.timeIntervalSinceNow)
        expiryTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self, self.generation == current else { return }
            self.expire()
        }
    }

    private func validAccessToken(_ current: UUID) async throws -> String {
        guard current == generation else { throw CancellationError() }
        if let accessToken, expiresAt.timeIntervalSinceNow > 60 { return accessToken }
        if credential != nil { return try await refreshAccessToken(current, replacing: accessToken) }
        guard let accessToken, expiresAt > Date() else { throw UOATransport.Failure(status: 401) }
        return accessToken
    }

    /// Single-flight rotation. A token a concurrent caller already replaced is reused.
    private func refreshAccessToken(_ current: UUID, replacing stale: String? = nil) async throws -> String {
        guard current == generation else { throw CancellationError() }
        if let accessToken, accessToken != stale, expiresAt.timeIntervalSinceNow > 60 { return accessToken }
        if let refreshTask { return try await refreshTask.value }
        guard let stored = credential else { throw SessionRejected() }
        let task = Task { () throws -> String in
            let body = try JSONSerialization.data(withJSONObject: [
                "grant_type": "refresh_token", "refresh_token": stored.refreshToken, "client_id": stored.clientID
            ])
            do {
                let grant = try UOATokenGrant(data: try await transport("/oauth/token", "POST", nil, body, nil).data)
                guard generation == current else { throw CancellationError() }
                accept(grant, clientID: stored.clientID)
                return grant.accessToken
            } catch let failure as UOATransport.Failure where failure.rejectsCredential {
                guard generation == current else { throw CancellationError() }
                forgetCredential()
                throw SessionRejected()
            }
        }
        refreshTask = task
        defer { if refreshTask == task { refreshTask = nil } }
        return try await task.value
    }

    private func send(_ path: String, method: String, token: String, body: Data?, version: String?, current: UUID) async throws -> UOATransport.Response {
        let response = try await transport(path, method, token, body, version)
        guard current == generation else { throw CancellationError() }
        return response
    }

    private func forgetCredential() {
        storage.clear()
        credential = nil
    }

    private func expire() {
        signOut()
        error = UOATransport.Failure(status: 401).localizedDescription
    }

    /// Returns to the signed-out state. Storage survives only a restore that failed in transit.
    private func reset(clearStorage: Bool) {
        generation = UUID()
        session?.cancel()
        session = nil
        expiryTask?.cancel()
        expiryTask = nil
        refreshTask?.cancel()
        refreshTask = nil
        if clearStorage { forgetCredential() } else { credential = nil }
        accessToken = nil
        expiresAt = .distantPast
        profile = nil
        avatar = nil
        signingIn = false
        error = nil
        bookmarks.useLocalBookmarks()
    }

    /// Best effort: the local session is already gone, so every revocation failure is ignored.
    private func revoke(_ issued: UOAStoredSession) {
        let transport = transport
        Task {
            guard let body = try? JSONSerialization.data(withJSONObject: ["token": issued.refreshToken, "client_id": issued.clientID]) else { return }
            _ = try? await transport("/oauth/revoke", "POST", nil, body, nil)
        }
    }

    // MARK: - Interactive sign-in

    private func authorize(_ attempt: UUID) async {
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

    private func registeredClient() async throws -> String {
        let body = try JSONSerialization.data(withJSONObject: [
            "app_id": "com.unlikeotherai.kelpie", "client_name": UOAPresentation.clientName, "redirect_uris": [UOAAuthorization.callback],
            "token_endpoint_auth_method": "none", "scope": UOAAuthorization.scopes
        ])
        let response = try await transport("/oauth/register", "POST", nil, body, nil)
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
            let grant = try UOATokenGrant(data: try await transport("/oauth/token", "POST", nil, body, nil).data)
            guard generation == attempt else { return }
            accept(grant, clientID: clientID)
            try await finishSignIn(attempt)
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
