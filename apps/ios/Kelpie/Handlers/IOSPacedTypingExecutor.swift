import Foundation

/// Sequences already-planned scalars; each mutation callback owns the renderer fences.
@MainActor
enum IOSPacedTypingExecutor {
    static func run(
        clearFirst: Bool,
        scalars: [String],
        delayMs: Int,
        apply: (String, String, Bool) async throws -> Void,
        wait: (Int) async throws -> Void
    ) async throws {
        var completed = false
        do {
            if clearFirst {
                try await apply("fill", "", false)
                completed = true
            }
            for (index, scalar) in scalars.enumerated() {
                if index > 0 { try await wait(delayMs) }
                try await apply("type", scalar, clearFirst || index > 0)
                completed = true
            }
        } catch let failure as IOSWorkflowFailure {
            throw IOSWorkflowFailure(failure.code, mayHaveCompleted: completed || failure.mayHaveCompleted)
        } catch {
            throw IOSWorkflowFailure("INPUT_INTERRUPTED", mayHaveCompleted: completed)
        }
    }
}
