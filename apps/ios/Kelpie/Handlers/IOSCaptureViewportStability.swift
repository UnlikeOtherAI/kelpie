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
        admissible: (IOSWorkflowTab.Viewport) -> Bool = { _ in true },
        now: () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
        pause: () async throws -> Void = { try await Task.sleep(nanoseconds: 20_000_000) }
    ) async throws -> IOSWorkflowTab.Viewport? {
        var stability = Self()
        repeat {
            try await check()
            guard now() < deadline else { throw IOSWorkflowFailure("CAPTURE_VIEWPORT_UNSTABLE") }
            let candidate = try await read()
            try await check()
            guard now() < deadline else { throw IOSWorkflowFailure("CAPTURE_VIEWPORT_UNSTABLE") }
            guard let viewport = candidate else { return nil }
            if stability.observe(viewport, at: now(), admissible: admissible(viewport)) { return viewport }
            do { try await pause() } catch { try await check(); throw error }
        } while now() < deadline
        throw IOSWorkflowFailure("CAPTURE_VIEWPORT_UNSTABLE")
    }

    static func matchesInsets(
        _ viewport: IOSWorkflowTab.Viewport, top: CGFloat, bottom: CGFloat, left: CGFloat = 0, right: CGFloat = 0
    ) -> Bool {
        let native = viewport.bounds
        guard native.width > 0, native.height > 0, viewport.visible.width > 0,
              [top, bottom, left, right].allSatisfy({ $0.isFinite && $0 >= 0 }),
              top + bottom < native.height, left + right < native.width else { return false }
        let ratio = viewport.visible.width / (native.width - left - right)
        let expectedHeight = (native.height - top - bottom) * ratio
        return expectedHeight.isFinite && abs(viewport.visible.height - expectedHeight) <= max(1, ratio)
    }

    mutating func observe(_ viewport: IOSWorkflowTab.Viewport, at time: TimeInterval, admissible: Bool = true) -> Bool {
        if !admissible {
            previous = nil
            stableSince = time
            return false
        }
        if previous != viewport {
            previous = viewport
            stableSince = time
            return false
        }
        return time - stableSince >= 0.2
    }
}
