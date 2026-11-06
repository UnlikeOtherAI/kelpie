#if DEBUG && KELPIE_HOSTED_STREAM_TEST
import Foundation

/// `inspect` must include its own post-read grant check. No await separates it from publication.
@MainActor
enum ScriptHostedOverlayAudit {
    static func publish(
        check: () async throws -> Void,
        inspect: () async throws -> Bool,
        current: () -> Bool,
        move: () -> Bool
    ) async -> Bool {
        do {
            try await check()
            guard try await inspect(), current() else { return false }
            return move()
        } catch { return false }
    }
}
#endif
