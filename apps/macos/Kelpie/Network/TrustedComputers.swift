import Foundation

/// Product permissions keyed by socket IP. UOA identity and account grants stay separate.
final class TrustedComputers: @unchecked Sendable {
    struct Computer: Decodable, Identifiable {
        let address: String
        let name: String
        let approvedAt: Double
        var id: String { address }
    }

    private let path: String

    init(pairingStoreURL: URL?) {
        path = pairingStoreURL?.deletingLastPathComponent()
            .appendingPathComponent("trusted-computers.json").path ?? ""
    }

    static func canonicalAddress(_ address: String) -> String? {
        request(path: "", operation: "normalize", body: ["address": address])["address"] as? String
    }

    static func safeHost(_ host: String) -> Bool {
        request(path: "", operation: "safe-host", body: ["host": host])["safe"] as? Bool == true
    }

    func clientId(for address: String) -> String? {
        guard let canonical = Self.canonicalAddress(address),
              perform("check", ["address": canonical])["trusted"] as? Bool == true else { return nil }
        return "host:\(canonical)"
    }

    func approve(address: String, name: String) -> Bool {
        perform("approve", ["address": address, "name": name])["success"] as? Bool == true
    }

    func revoke(address: String) -> Bool {
        perform("revoke", ["address": address])["success"] as? Bool == true
    }

    func list() -> [Computer] {
        guard let data = try? JSONSerialization.data(withJSONObject: perform("list", [:])["computers"] ?? []) else { return [] }
        return (try? JSONDecoder().decode([Computer].self, from: data)) ?? []
    }

    private func perform(_ operation: String, _ body: [String: String]) -> [String: Any] {
        Self.request(path: path, operation: operation, body: body)
    }

    private static func request(path: String, operation: String, body: [String: String]) -> [String: Any] {
        guard let data = try? JSONSerialization.data(withJSONObject: body),
              let json = String(data: data, encoding: .utf8),
              let output = kelpie_peer_trust_request(path, operation, json) else { return [:] }
        defer { kelpie_free_string(output) }
        return (try? JSONSerialization.jsonObject(with: Data(String(cString: output).utf8))) as? [String: Any] ?? [:]
    }
}
