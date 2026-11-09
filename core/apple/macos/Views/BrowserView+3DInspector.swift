extension BrowserView {
    @MainActor
    func toggle3DInspector() async {
        if serverState.handlerContext.isIn3DInspector || isIn3DInspector {
            await exit3DInspector()
            return
        }

        try? await serverState.handlerContext.enter3DInspector(windowId: windowId)
        // Use a JS string expression so WebKit returns a String rather than NSNumber,
        // avoiding the "1" vs "true" mismatch from evaluateJSReturningString.
        let active = try? await serverState.handlerContext.evaluate3DInspectorJS("window.__m3d ? 'true' : 'false'", windowId: windowId)
        guard active as? String == "true" else { return }

        serverState.handlerContext.isIn3DInspector = true
        isIn3DInspector = true
        inspectorMode = "rotate"
        _ = try? await serverState.handlerContext.evaluate3DInspectorJS(Snapshot3DBridge.setModeScript(inspectorMode), windowId: windowId)
    }

    @MainActor
    func exit3DInspector() async {
        guard serverState.handlerContext.isIn3DInspector || isIn3DInspector else { return }
        _ = try? await serverState.handlerContext.evaluate3DInspectorJS(Snapshot3DBridge.exitScript, windowId: windowId)
        serverState.handlerContext.mark3DInspectorInactive(notify: true)
        isIn3DInspector = false
        inspectorMode = "rotate"
    }

    @MainActor
    func set3DInspectorMode(_ mode: String) async {
        guard serverState.handlerContext.isIn3DInspector || isIn3DInspector else { return }
        let normalized = mode == "scroll" ? "scroll" : "rotate"
        _ = try? await serverState.handlerContext.evaluate3DInspectorJS(Snapshot3DBridge.setModeScript(normalized), windowId: windowId)
        inspectorMode = normalized
    }

    @MainActor
    func zoom3DInspector(by delta: Double) async {
        guard serverState.handlerContext.isIn3DInspector || isIn3DInspector else { return }
        _ = try? await serverState.handlerContext.evaluate3DInspectorJS(Snapshot3DBridge.zoomByScript(delta), windowId: windowId)
    }

    @MainActor
    func reset3DInspectorView() async {
        guard serverState.handlerContext.isIn3DInspector || isIn3DInspector else { return }
        _ = try? await serverState.handlerContext.evaluate3DInspectorJS(Snapshot3DBridge.resetViewScript, windowId: windowId)
    }
}
