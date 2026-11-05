import Foundation

/// A first frame is admitted only after the complete renderer viewport settles.
@MainActor
struct IOSCaptureViewportStability {
    private var previous: IOSWorkflowTab.Viewport?
    private var stableSince: TimeInterval = 0

    static func wait(
        deadline: TimeInterval,
        check: () async throws -> Void,
        read: () async throws -> IOSWorkflowTab.Viewport?,
        now: () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
        pause: () async throws -> Void = { try await Task.sleep(nanoseconds: 20_000_000) }
    ) async throws -> IOSWorkflowTab.Viewport? {
        var stability = Self()
        repeat {
            try await check()
            guard now() < deadline else { throw IOSWorkflowFailure("CAPTURE_VIEWPORT_UNSTABLE") }
            guard let viewport = try await read() else { return nil }
            try await check()
            guard now() < deadline else { throw IOSWorkflowFailure("CAPTURE_VIEWPORT_UNSTABLE") }
            if stability.observe(viewport, at: now()) { return viewport }
            try await pause()
        } while now() < deadline
        throw IOSWorkflowFailure("CAPTURE_VIEWPORT_UNSTABLE")
    }

    mutating func observe(_ viewport: IOSWorkflowTab.Viewport, at time: TimeInterval) -> Bool {
        if previous != viewport {
            previous = viewport
            stableSince = time
            return false
        }
        return time - stableSince >= 0.2
    }
}
