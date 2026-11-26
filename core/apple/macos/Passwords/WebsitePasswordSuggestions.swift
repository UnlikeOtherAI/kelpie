import AuthenticationServices

/// Safari receives site and username metadata here. The password is read from
/// Keychain only when macOS asks our extension for the selected credential.
@MainActor
enum WebsitePasswordSuggestions {
    static func identity(_ login: WebsitePasswordStore.Login) -> ASPasswordCredentialIdentity {
        let service = ASCredentialServiceIdentifier(identifier: login.origin, type: .URL)
        return ASPasswordCredentialIdentity(serviceIdentifier: service, user: login.username, recordIdentifier: login.account)
    }

    static func matches(_ login: WebsitePasswordStore.Login, service: ASCredentialServiceIdentifier) -> Bool {
        switch service.type {
        case .URL:
            guard let url = URL(string: service.identifier) else { return false }
            return WebsitePasswordStore.Login(url: url, username: login.username) == login
        case .domain:
            guard let url = URL(string: login.origin), url.port == nil else { return false }
            return url.host()?.caseInsensitiveCompare(service.identifier) == .orderedSame
        default: return false
        }
    }

    static func replace(from store: WebsitePasswordStore) async throws {
        let identities: [any ASCredentialIdentity] = try store.logins().map(identity)
        try await ASCredentialIdentityStore.shared.replaceCredentialIdentities(identities)
    }

    private static var queued: WebsitePasswordStore?
    private static var refreshing = false

    static func refresh(from store: WebsitePasswordStore) {
        guard store.accessGroup != nil else { return }
        queued = store
        guard !refreshing else { return }
        refreshing = true
        Task {
            defer { refreshing = false }
            while let latest = queued {
                queued = nil
                if await ASCredentialIdentityStore.shared.state().isEnabled {
                    // A busy or disabled system store is reconciled again on app
                    // activation. Keychain remains authoritative for every fill.
                    try? await replace(from: latest)
                }
            }
        }
    }
}
