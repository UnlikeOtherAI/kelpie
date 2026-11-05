import UIKit

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
        guard top.isFinite, bottom.isFinite, top >= 0, bottom >= 0, top + bottom < viewport.bounds.height,
              let content = IOSWorkflowTab.contentRect(
                  bounds: viewport.bounds,
                  insets: UIEdgeInsets(top: top, left: left, bottom: bottom, right: right),
                  visible: viewport.visible.size
              ) else { return false }
        let pixelAllowance = content.width / viewport.visible.width
        return content.maxY >= viewport.bounds.height - bottom - pixelAllowance
    }

    enum SnapshotDecision { case coherent, discard, fenced }

    static func snapshotDecision(
        before: IOSWorkflowTab.Viewport,
        after: IOSWorkflowTab.Viewport,
        hasBaseline: Bool,
        targetBound: Bool,
        now: TimeInterval,
        deadline: TimeInterval
    ) -> SnapshotDecision {
        if before == after { return .coherent }
        return !hasBaseline && !targetBound && now < deadline ? .discard : .fenced
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
