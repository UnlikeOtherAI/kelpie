@_implementationOnly import KelpieNative
import Foundation

/// Durable computer permission follows an Ed25519 key. IP is display data only.
final class TrustedComputers: @unchecked Sendable {
    struct Computer: Decodable, Identifiable {
        let publicKey: String
        let address: String
        let name: String
        let approvedAt: Double
        var id: String { publicKey }
    }
    struct Request: Decodable, Equatable {
        let requestId: String
        let clientName: String
        let sourceAddress: String
        let publicKey: String
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
    func clientId(for address: String, token: String = "") -> String? {
        perform("authorize", ["address": address, "token": token])["clientId"] as? String
    }
    func start(body: [String: Any], source: String) -> (status: Int, json: [String: Any]) {
        let response = perform("start", ["address": source, "body": body])
        return (response["status"] as? Int ?? 500, response["body"] as? [String: Any] ?? ["success": false])
    }
    func status(requestId: String, source: String) -> [String: Any] {
        perform("status", ["requestId": requestId, "address": source])
    }
    func pending() -> Request? { decode(perform("pending", [:])) }
    func approve(requestId: String) -> Bool {
        perform("approve", ["requestId": requestId])["success"] as? Bool == true
    }
    func deny(requestId: String) { _ = perform("deny", ["requestId": requestId]) }
    func revoke(publicKey: String) -> Bool {
        perform("revoke", ["publicKey": publicKey])["success"] as? Bool == true
    }
    func list() -> [Computer] { decode(perform("list", [:])["computers"] ?? []) ?? [] }
    private func decode<T: Decodable>(_ value: Any) -> T? {
        guard JSONSerialization.isValidJSONObject(value), let data = try? JSONSerialization.data(withJSONObject: value) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }
    private func perform(_ operation: String, _ body: [String: Any]) -> [String: Any] {
        Self.request(path: path, operation: operation, body: body)
    }
    private static func request(path: String, operation: String, body: [String: Any]) -> [String: Any] {
        guard let data = try? JSONSerialization.data(withJSONObject: body),
              let json = String(data: data, encoding: .utf8),
              let output = kelpie_peer_trust_request(path, operation, json) else { return [:] }
        defer { kelpie_free_string(output) }
        return (try? JSONSerialization.jsonObject(with: Data(String(cString: output).utf8))) as? [String: Any] ?? [:]
    }
}
