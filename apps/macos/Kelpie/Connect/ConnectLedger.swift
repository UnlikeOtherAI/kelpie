import Foundation

@MainActor
final class ConnectLedger {
    private let handle: KelpieConnectRef
    private static let key = "nessie.connect.journal.v1"

    init(owner: String) throws {
        let saved = SecretStore.shared.get(Self.key) ?? ""
        guard let handle = kelpie_connect_create(saved, owner) else { throw Failure.journal }
        self.handle = handle
    }

    deinit { kelpie_connect_destroy(handle) }

    func execute(_ operation: String, _ body: [String: Any]) throws -> [String: Any] {
        let input = try JSONSerialization.data(withJSONObject: body)
        guard let raw = kelpie_connect_execute(handle, operation, String(decoding: input, as: UTF8.self)) else {
            throw Failure.protocolViolation
        }
        defer { kelpie_connect_free(raw) }
        guard let envelope = try JSONSerialization.jsonObject(with: Data(String(cString: raw).utf8)) as? [String: Any],
              let state = envelope["state"], let decision = envelope["decision"] as? [String: Any] else {
            throw Failure.protocolViolation
        }
        let data = try JSONSerialization.data(withJSONObject: state)
        try SecretStore.shared.setDurably(Self.key, value: String(decoding: data, as: UTF8.self))
        return decision
    }

    static func clear() throws { try SecretStore.shared.setDurably(key, value: "") }

    enum Failure: Error { case journal, protocolViolation }
}
