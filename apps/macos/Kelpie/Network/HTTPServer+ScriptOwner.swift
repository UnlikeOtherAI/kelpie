import Foundation

extension HTTPServer {
    /// Captures the admitted listener and current pairing authority; the body cannot supply a grant.
    func scriptGrant(_ request: ParsedHTTPRequest, clientID: String, listener: UUID) -> ScriptRequestOwner? {
        guard let authorization = request.headers["authorization"]?.first,
              authorization.lowercased().hasPrefix("bearer ") else { return nil }
        let bearer = String(authorization.dropFirst(7)).trimmingCharacters(in: .whitespaces)
        let check = ParsedHTTPRequest(
            method: "POST",
            path: "/v1/play-script",
            query: "",
            headers: ["authorization": [authorization]],
            body: Data(),
            sourceAddress: request.sourceAddress,
            hasTransferEncoding: false
        )
        return ScriptRequestOwner(listener: listener, clientID: clientID, bearer: bearer) { [scriptListener, pairingStore] in
            guard scriptListener.incarnation == listener else { return false }
            let result = await AccountPairingAuthorization(store: pairingStore).evaluate(check)
            return result == .authenticated(clientId: clientID) && scriptListener.incarnation == listener
        }
    }
}
