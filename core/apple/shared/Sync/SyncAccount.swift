import Combine
import Foundation

/// The account a sync run belongs to. Every asynchronous step captures it and checks
/// it again before any effect, so work from a previous sign-in is discarded.
struct SyncFence: Equatable, Sendable {
    let subject: String
    let generation: String
}

/// UOA as cookie sync needs it: the live subject and session generation, and the two
/// transcript-bound pairing ticket calls. Implementations never read or copy tokens.
@MainActor
protocol SyncAccount: AnyObject {
    var fence: SyncFence? { get }
    /// Called after every sign-in, sign-out or account change.
    func observe(_ handler: @escaping @MainActor () -> Void)
    /// `POST /oauth/kelpie/pair {challenge, clientId}` → the pairing ticket.
    func issueTicket(challenge: String, clientId: String) async throws -> String
    /// `POST /oauth/kelpie/pair/validate {ticket, challenge, clientId}` → `active`.
    func validateTicket(_ ticket: String, challenge: String, clientId: String) async throws -> Bool
}

/// The signed-in UOA session, through `UOAAccount.request`.
@MainActor
final class UOASyncAccount: SyncAccount {
    enum Failure: Error { case protocolViolation }

    private let account: UOAAccount
    private var subscription: AnyCancellable?

    init(account: UOAAccount) {
        self.account = account
    }

    convenience init() {
        self.init(account: .shared)
    }

    var fence: SyncFence? {
        guard let subject = account.profile?.sub, let generation = account.pairingSession else { return nil }
        return SyncFence(subject: subject, generation: generation)
    }

    func observe(_ handler: @escaping @MainActor () -> Void) {
        // `@Published` emits before the new value is stored; read the fence on the next turn.
        subscription = account.$profile.sink { _ in
            Task { @MainActor in handler() }
        }
    }

    func issueTicket(challenge: String, clientId: String) async throws -> String {
        let body = try JSONSerialization.data(withJSONObject: ["challenge": challenge, "clientId": clientId])
        let response = try await account.request("/oauth/kelpie/pair", method: "POST", body: body)
        guard let json = SyncJSON.object(response.data), let ticket = json["pairing_ticket"] as? String,
              !ticket.isEmpty, ticket.utf8.count <= 8192 else { throw Failure.protocolViolation }
        return ticket
    }

    /// A refused proof is `false`; only transport failures and the account's own
    /// rejection (401) throw.
    func validateTicket(_ ticket: String, challenge: String, clientId: String) async throws -> Bool {
        let body = try JSONSerialization.data(withJSONObject: ["ticket": ticket, "challenge": challenge, "clientId": clientId])
        do {
            let response = try await account.request("/oauth/kelpie/pair/validate", method: "POST", body: body)
            return SyncJSON.object(response.data)?["active"] as? Bool == true
        } catch let failure as UOATransport.Failure where (400..<500).contains(failure.status) && failure.status != 401 {
            return false
        }
    }
}
