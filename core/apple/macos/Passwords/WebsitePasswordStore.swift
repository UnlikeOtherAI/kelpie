import Foundation
import Security

/// Only Kelpie website passwords share this service. Settings reads item attributes only.
struct WebsitePasswordStore {
    struct Login: Hashable, Identifiable {
        let origin: String
        let username: String
        var id: Self { self }

        init?(url: URL, username: String) {
            guard url.scheme?.lowercased() == "https", let host = url.host()?.lowercased(),
                  !host.isEmpty, url.user == nil, url.password == nil, !username.isEmpty else { return nil }
            var components = URLComponents()
            components.scheme = "https"
            components.host = host
            components.port = url.port == 443 ? nil : url.port
            guard let origin = components.string else { return nil }
            self.origin = origin
            self.username = username
        }

        var account: String {
            // A URL origin cannot contain a newline. Usernames can, so split only once.
            origin + "\n" + username
        }

        init?(account: String) {
            guard let separator = account.firstIndex(of: "\n"),
                  let url = URL(string: String(account[..<separator])) else { return nil }
            self.init(url: url, username: String(account[account.index(after: separator)...]))
            guard self.account == account else { return nil }
        }
    }

    struct Failure: LocalizedError {
        let status: OSStatus
        var errorDescription: String? { SecCopyErrorMessageString(status, nil) as String? }
    }

    let service: String
    let accessGroup: String?

    init(service: String, accessGroup: String? = nil) {
        self.service = service
        self.accessGroup = accessGroup
    }

    static func sharedWithProvider(hostID: String) -> Self {
        let service = hostID + ".website-passwords"
        return Self(service: service, accessGroup: "23B7GTLBN7." + service)
    }

    private var items: [String: Any] {
        var query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service]
        if let accessGroup {
            query[kSecUseDataProtectionKeychain as String] = true
            query[kSecAttrAccessGroup as String] = accessGroup
        }
        return query
    }

    private func item(_ login: Login) -> [String: Any] {
        var query = items
        query[kSecAttrAccount as String] = login.account
        return query
    }

    func logins() throws -> [Login] {
        var query = items
        query[kSecReturnAttributes as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitAll
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return [] }
        try check(status)
        guard let rows = result as? [[String: Any]] else { throw Failure(status: errSecDecode) }
        return rows.compactMap { row in
            (row[kSecAttrAccount as String] as? String).flatMap(Login.init(account:))
        }.sorted { ($0.origin, $0.username) < ($1.origin, $1.username) }
    }

    func save(_ password: String, for login: Login) throws {
        guard !password.isEmpty else { throw Failure(status: errSecParam) }
        let query = item(login)
        let values: [String: Any] = [
            kSecAttrLabel as String: "Kelpie password for " + login.origin,
            kSecValueData as String: Data(password.utf8)
        ]
        var addition = query.merging(values) { _, new in new }
        if accessGroup != nil { addition[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly }
        let status = SecItemAdd(addition as CFDictionary, nil)
        if status == errSecDuplicateItem {
            try check(SecItemUpdate(query as CFDictionary, values as CFDictionary))
        } else {
            try check(status)
        }
    }

    func password(for login: Login) throws -> String {
        var query = item(login)
        query[kSecReturnData as String] = true
        var result: CFTypeRef?
        try check(SecItemCopyMatching(query as CFDictionary, &result))
        guard let data = result as? Data, let password = String(data: data, encoding: .utf8) else {
            throw Failure(status: errSecDecode)
        }
        return password
    }

    func delete(_ login: Login?) throws {
        var query = login.map(item) ?? items
        if login == nil && accessGroup == nil { query[kSecMatchLimit as String] = kSecMatchLimitAll }
        let status = SecItemDelete(query as CFDictionary)
        if status != errSecItemNotFound { try check(status) }
    }

    private func check(_ status: OSStatus) throws {
        if status != errSecSuccess { throw Failure(status: status) }
    }
}
