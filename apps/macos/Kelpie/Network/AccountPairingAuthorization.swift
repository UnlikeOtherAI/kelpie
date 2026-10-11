import Foundation

/// Same-account access uses UOA's live decision and the existing in-memory pairing store.
/// General account credentials never arrive over the LAN; only a challenge-bound ticket does.
struct AccountPairingAuthorization {
    typealias Session = @MainActor () -> String?
    typealias Verify = @MainActor (_ ticket: String, _ challenge: String, _ clientId: String, _ session: String) async -> Double?
    let store: PairingStore
    var session: Session = { UOAAccount.shared.pairingSession }
    var verify: Verify = { await UOAAccount.shared.verifyLocalPairing(ticket: $0, challenge: $1, clientId: $2, session: $3) }

    static func handles(_ body: Data) -> Bool {
        let value = try? JSONSerialization.jsonObject(with: body) as? [String: Any]
        return value?["account"] as? Bool == true
    }

    func handlePost(body: Data, sourceAddress: String) async -> (status: Int, json: [String: Any]) {
        guard let value = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
              let clientId = value["clientId"] as? String, !clientId.isEmpty, clientId.count <= 200 else {
            return error(400, "MISSING_PARAM", "clientId is required")
        }
        guard let current = await session() else {
            return error(409, "ACCOUNT_PAIRING_UNAVAILABLE", "Kelpie is not signed in")
        }
        if value["accountTicket"] != nil || value["requestId"] != nil {
            guard let ticket = value["accountTicket"] as? String, !ticket.isEmpty, ticket.utf8.count <= 8192,
                  let challenge = value["requestId"] as? String,
                  let pending = store.pendingRequest(requestId: challenge), pending.clientId == clientId,
                  pending.sourceAddress == sourceAddress, pending.accountSession == current else {
                return error(403, "ACCOUNT_AUTH_FAILED", "Account pairing verification failed")
            }
            guard let expiry = await verify(ticket, challenge, clientId, current), expiry > now(), expiry <= now() + 120_000,
                  await session() == current else {
                return error(403, "ACCOUNT_AUTH_FAILED", "Account pairing verification failed")
            }
            let grantedExpiry = min(expiry, pending.expiresAt)
            let grant = PairingStore.AccountGrant(
                session: current, ticket: ticket, challenge: challenge, expiresAt: grantedExpiry, sourceAddress: sourceAddress
            )
            guard store.approve(requestId: challenge, persist: false, accountGrant: grant) != nil,
                  let issued = store.takeIssuance(for: challenge, sourceAddress: sourceAddress) else {
                return error(403, "ACCOUNT_AUTH_FAILED", "Account pairing verification failed")
            }
            return (200, ["status": "approved", "scope": "session", "token": issued.token, "expiresAt": grantedExpiry])
        }
        switch store.startPairing(
            clientId: clientId, clientName: value["clientName"] as? String ?? "", sourceAddress: sourceAddress, accountSession: current
        ) {
        case .denied: return error(403, "DENIED", "Pair requests from this source are currently suppressed")
        case .created(let pending):
            return (202, ["status": "account_challenge", "requestId": pending.requestId, "expiresAt": pending.expiresAt])
        }
    }

    /// Manual bearer validation stays synchronous. Account grants require a fresh UOA decision
    /// before each API/MCP request, followed by another local revocation/session check.
    func evaluate(_ request: ParsedHTTPRequest) async -> AuthDecision {
        let middleware = AuthMiddleware(store: store)
        let decision = middleware.evaluate(request)
        guard case .reject(401, _, _) = decision,
              let header = request.headers["authorization"]?.first, header.lowercased().hasPrefix("bearer ") else { return decision }
        let token = String(header.dropFirst(7)).trimmingCharacters(in: .whitespaces)
        guard let approval = store.accountApproval(token), let grant = approval.accountGrant,
              await session() == grant.session,
              let expiry = await verify(grant.ticket, grant.challenge, approval.clientId, grant.session), expiry > now(),
              await session() == grant.session, store.accountApproval(token) == approval else { return decision }
        return middleware.evaluate(request, verifiedAccountClientId: approval.clientId)
    }

    private func now() -> Double { Date().timeIntervalSince1970 * 1_000 }
    private func error(_ status: Int, _ code: String, _ message: String) -> (status: Int, json: [String: Any]) {
        (status, ["success": false, "error": ["code": code, "message": message]])
    }
}

extension UOAAccount {
    /// UOA compares both live subjects; a copied email/name or unsigned subject never authorizes access.
    func verifyLocalPairing(ticket: String, challenge: String, clientId: String, session: String) async -> Double? {
        guard pairingSession == session else { return nil }
        do {
            let body = try JSONSerialization.data(withJSONObject: ["ticket": ticket, "challenge": challenge, "clientId": clientId])
            let response = try await request("/oauth/kelpie/pair/validate", method: "POST", body: body)
            struct Decision: Decodable { let active: Bool; let expires_at: Double }
            let decision = try JSONDecoder().decode(Decision.self, from: response.data)
            guard decision.active, pairingSession == session else { return nil }
            return decision.expires_at
        } catch { return nil }
    }
}
