import Foundation

/// Sequences already-planned scalars; each mutation callback owns the renderer fences.
@MainActor
enum IOSPacedTypingExecutor {
    static func isAcknowledgement(_ body: [String: Any], token: String?) -> Bool {
        guard let token, !token.isEmpty else { return false }
        return body["ok"] as? Bool == true && (body["error"] == nil || body["error"] is NSNull) &&
            body["sensitive"] is Bool && body["sensitivityKnown"] is Bool &&
            body["mayHaveCompleted"] as? Bool == true && body["token"] as? String == token &&
            body["inputGuarantee"] as? String == "synthetic-coordinate"
    }

    static func needsPrivacyLatch(_ body: [String: Any], token: String?) -> Bool {
        if isAcknowledgement(body, token: token) { return false }
        let refusedBeforeInput = body["ok"] as? Bool == false && body["mayHaveCompleted"] as? Bool == false &&
            body["error"] is String && hasKnownSensitivity(body)
        return !refusedBeforeInput
    }

    static func hasKnownSensitivity(_ body: [String: Any]) -> Bool {
        body["sensitive"] as? Bool == true ||
            (body["sensitive"] as? Bool == false && body["sensitivityKnown"] as? Bool == true)
    }

    static func requireKnownSensitivity(_ known: Bool?, hasContinuation: Bool) throws {
        guard known == true || !hasContinuation else { throw IOSWorkflowFailure("INPUT_UNCERTAIN", mayHaveCompleted: true) }
    }

    static func run(
        clearFirst: Bool,
        scalars: [String],
        delayMs: Int,
        apply: (String, String, Bool, Bool) async throws -> Void,
        wait: (Int) async throws -> Void
    ) async throws {
        var completed = false
        do {
            if clearFirst {
                try await apply("fill", "", false, scalars.isEmpty)
                completed = true
            }
            for (index, scalar) in scalars.enumerated() {
                if index > 0 { try await wait(delayMs) }
                try await apply("type", scalar, clearFirst || index > 0, index == scalars.count - 1)
                completed = true
            }
        } catch let failure as IOSWorkflowFailure {
            throw IOSWorkflowFailure(failure.code, mayHaveCompleted: completed || failure.mayHaveCompleted)
        } catch {
            throw IOSWorkflowFailure("INPUT_INTERRUPTED", mayHaveCompleted: completed)
        }
    }
}
