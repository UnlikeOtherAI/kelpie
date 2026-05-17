import Foundation

/// Handler for the unauthenticated `/v1/pair` and `/v1/pair/status` endpoints
/// plus authenticated `DELETE /v1/pair`. Kept separate from the request
/// dispatcher so the auth + CSRF state machine has a single, testable home.
struct PairEndpoints {
    let store: PairingStore
    /// Called on the main actor after a new pending entry is created so the
    /// SwiftUI prompt can refresh. Nil during tests.
    let onPendingChanged: (@MainActor () -> Void)?

    /// POST /v1/pair
    func handlePairPost(body: Data, sourceAddress: String) -> (status: Int, json: [String: Any]) {
        guard let parsed = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else {
            return (400, errorBody(code: "INVALID_JSON", message: "Request body is not valid JSON"))
        }
        guard let clientId = parsed["clientId"] as? String, !clientId.isEmpty else {
            return (400, errorBody(code: "MISSING_PARAM", message: "clientId is required"))
        }
        let clientName = (parsed["clientName"] as? String) ?? ""

        switch store.startPairing(clientId: clientId, clientName: clientName, sourceAddress: sourceAddress) {
        case .denied:
            return (403, errorBody(code: "DENIED", message: "Pair requests from this source are currently suppressed"))
        case .created(let req):
            if let hook = onPendingChanged {
                Task { @MainActor in hook() }
            }
            return (202, [
                "status": "pending",
                "requestId": req.requestId,
                "expiresAt": Int(req.expiresAt),
                "sourceAddress": req.sourceAddress
            ])
        }
    }

    /// GET /v1/pair/status?requestId=…
    func handlePairStatus(query: String, sourceAddress: String) -> (status: Int, json: [String: Any]) {
        guard let requestId = HTTPRequestParser.queryValue("requestId", in: query), !requestId.isEmpty else {
            return (400, errorBody(code: "MISSING_PARAM", message: "requestId is required"))
        }
        // Source-address binding: if the pending request exists but the
        // socket peer differs, do not leak status at all.
        if let pending = store.pendingRequest(requestId: requestId) {
            if pending.sourceAddress != sourceAddress {
                return (200, ["status": "not_found"])
            }
            return (200, ["status": "pending"])
        }
        // The pending entry might have been consumed by approval; check both
        // session and persistent stores for the issuance side-channel.
        if let issuance = store.takeIssuance(for: requestId, sourceAddress: sourceAddress) {
            return (200, [
                "status": "approved",
                "scope": issuance.scope,
                "token": issuance.token
            ])
        }
        // Could be denied — denial leaves no breadcrumb, return not_found to
        // avoid leaking which clientId was denied.
        if store.wasRecentlyDenied(sourceAddress: sourceAddress) {
            return (200, ["status": "denied"])
        }
        return (200, ["status": "not_found"])
    }

    /// DELETE /v1/pair (authenticated). Revokes the pairing identified by the
    /// validated bearer token. Any `clientId` query parameter is ignored.
    func handlePairDelete(authenticatedClientId: String) -> (status: Int, json: [String: Any]) {
        let removed = store.revoke(clientId: authenticatedClientId)
        return (200, ["success": removed])
    }

    /// GET /v1/get-device-info (unauthenticated, public capability advert).
    func handleGetDeviceInfo(name: String, platform: String, version: String) -> (status: Int, json: [String: Any]) {
        (200, [
            "name": name,
            "platform": platform,
            "version": version,
            "requiresPairing": true
        ])
    }

    private func errorBody(code: String, message: String) -> [String: Any] {
        ["success": false, "error": ["code": code, "message": message]]
    }
}
