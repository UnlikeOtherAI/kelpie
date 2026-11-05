import CoreFoundation
import Foundation

/// Sequences already-planned scalars; each mutation callback owns the renderer fences.
@MainActor
enum IOSPacedTypingExecutor {
    static func jsonBoolean(_ value: Any?) -> Bool? {
        guard let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() else { return nil }
        return number.boolValue
    }

    static func isAcknowledgement(_ body: [String: Any], token: String?) -> Bool {
        guard let token, !token.isEmpty else { return false }
        return jsonBoolean(body["ok"]) == true && body["error"] == nil &&
            jsonBoolean(body["sensitive"]) != nil && jsonBoolean(body["sensitivityKnown"]) != nil &&
            jsonBoolean(body["mayHaveCompleted"]) == true && body["token"] as? String == token &&
            body["inputGuarantee"] as? String == "synthetic-coordinate"
    }

    static func isRefusal(_ body: [String: Any]) -> Bool {
        guard let error = body["error"] as? String, !error.isEmpty else { return false }
        return jsonBoolean(body["ok"]) == false && jsonBoolean(body["mayHaveCompleted"]) != nil &&
            jsonBoolean(body["sensitive"]) != nil && jsonBoolean(body["sensitivityKnown"]) != nil
    }

    static func needsPrivacyLatch(_ body: [String: Any], token: String?) -> Bool {
        if jsonBoolean(body["sensitive"]) == true { return true }
        guard isAcknowledgement(body, token: token) || isRefusal(body) else { return true }
        return !hasKnownSensitivity(body)
    }

    static func hasKnownSensitivity(_ body: [String: Any]) -> Bool {
        jsonBoolean(body["sensitive"]) == true ||
            (jsonBoolean(body["sensitive"]) == false && jsonBoolean(body["sensitivityKnown"]) == true)
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
