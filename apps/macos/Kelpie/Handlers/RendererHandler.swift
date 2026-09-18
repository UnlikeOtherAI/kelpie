import Foundation

/// Handles set-renderer and get-renderer endpoints.
/// Triggers cookie migration and engine swap.
struct RendererHandler {
    let context: HandlerContext
    let rendererState: RendererState
    let onSwitch: (RendererState.Engine) async -> Void

    func register(on router: Router) {
        router.register("set-renderer") { body in await setRenderer(body) }
        router.register("get-renderer") { _ in await getRenderer() }
    }

    @MainActor
    private func setRenderer(_ body: [String: Any]) async -> [String: Any] {
        guard let engineStr = body["engine"] as? String else {
            return errorResponse(code: "MISSING_PARAM", message: "engine is required (webkit|chromium)")
        }
        guard let engine = RendererState.Engine(rawValue: engineStr) else {
            return errorResponse(code: "INVALID_PARAM", message: "engine must be webkit or chromium")
        }
        if engine == rendererState.activeEngine {
            return successResponse(["engine": engine.rawValue, "changed": false])
        }
        if engine == .chromium, let blocked = partitionedTabsBlockSwitch() { return blocked }

        await onSwitch(engine)

        return successResponse(["engine": engine.rawValue, "changed": true])
    }

    /// Refuses a switch to Chromium while any partitioned tab is open.
    ///
    /// Switching engines migrates cookies through a single shared jar. A
    /// partitioned tab has a data store of its own that CEF has no equivalent
    /// for, so the migration would either silently drop those sessions or merge
    /// them into one — both of which destroy the isolation the caller asked
    /// for. Refusing is the only honest option.
    ///
    /// Only the Chromium direction is blocked. Blocking both would trap a
    /// launch that restored partitioned tabs with Chromium already selected:
    /// the user could never get back to the engine those tabs need.
    @MainActor
    private func partitionedTabsBlockSwitch() -> [String: Any]? {
        let partitioned = WindowRegistry.shared.allEntriesIncludingDetached()
            .flatMap { $0.tabStore.tabs.compactMap(\.partition) }
        guard !partitioned.isEmpty else { return nil }
        let names = Set(partitioned).sorted().joined(separator: ", ")
        return errorResponse(
            code: "ENGINE_SWITCH_BLOCKED_BY_PARTITION",
            message: "Cannot switch to the Chromium engine while partitioned tabs are open (\(names)). " +
                "Partitioned storage cannot be migrated between engines. " +
                "Close those tabs or call delete-partition first."
        )
    }

    @MainActor
    private func getRenderer() async -> [String: Any] {
        successResponse([
            "engine": rendererState.activeEngine.rawValue,
            "available": RendererState.Engine.allCases.map(\.rawValue)
        ])
    }
}
