import SwiftUI
import WebKit

extension BrowserView {
    @MainActor
    func toggle3DInspector() async {
        if serverState.handlerContext.isIn3DInspector || isIn3DInspector {
            await exit3DInspector()
            return
        }

        _ = try? await serverState.handlerContext.evaluateJS(Snapshot3DBridge.enterScript)
        let active = try? await serverState.handlerContext.evaluateJSReturningString("!!window.__m3d")
        guard active == "true" else { return }

        serverState.handlerContext.isIn3DInspector = true
        isIn3DInspector = true
        inspectorMode = "rotate"
        _ = try? await serverState.handlerContext.evaluateJS(Snapshot3DBridge.setModeScript(inspectorMode))
    }

    @MainActor
    func exit3DInspector() async {
        guard serverState.handlerContext.isIn3DInspector || isIn3DInspector else { return }
        _ = try? await serverState.handlerContext.evaluateJS(Snapshot3DBridge.exitScript)
        serverState.handlerContext.mark3DInspectorInactive(notify: true)
        isIn3DInspector = false
        inspectorMode = "rotate"
    }

    @MainActor
    func set3DInspectorMode(_ mode: String) async {
        guard serverState.handlerContext.isIn3DInspector || isIn3DInspector else { return }
        let normalized = mode == "scroll" ? "scroll" : "rotate"
        _ = try? await serverState.handlerContext.evaluateJS(Snapshot3DBridge.setModeScript(normalized))
        inspectorMode = normalized
    }

    @MainActor
    func zoom3DInspector(by delta: Double) async {
        guard serverState.handlerContext.isIn3DInspector || isIn3DInspector else { return }
        _ = try? await serverState.handlerContext.evaluateJS(Snapshot3DBridge.zoomByScript(delta))
    }

    @MainActor
    func reset3DInspectorView() async {
        guard serverState.handlerContext.isIn3DInspector || isIn3DInspector else { return }
        _ = try? await serverState.handlerContext.evaluateJS(Snapshot3DBridge.resetViewScript)
    }

    // MARK: - Touchpad Mode

    func enterTouchpadMode() {
        touchpadMode = true
        OrientationManager.shared.lock = .landscape
        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
            scene.requestGeometryUpdate(.iOS(interfaceOrientations: .landscape))
            scene.keyWindow?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
        }
    }

    func exitTouchpadMode() {
        touchpadMode = false
        OrientationManager.shared.lock = .all
        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
            scene.keyWindow?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
        }
    }

    // MARK: - Debug Overlay

    func updateDebug() {
        let connectedScreens = UIApplication.shared.connectedScenes.compactMap { scene in
            (scene as? UIWindowScene)?.screen
        }
        var screensByID: [ObjectIdentifier: UIScreen] = [:]
        for screen in connectedScreens + [UIScreen.main] {
            screensByID[ObjectIdentifier(screen)] = screen
        }
        let screens = Array(screensByID.values)
        let mgr = ExternalDisplayManager.shared
        var lines: [String] = []

        for (i, screen) in screens.enumerated() {
            let origin = screen.bounds.origin
            let wx = Int(origin.x), wy = Int(origin.y)
            let ww = Int(screen.bounds.width), wh = Int(screen.bounds.height)
            let sc = Int(screen.scale), nat = Int(screen.nativeScale)
            lines.append("scr[\(i)] \(wx),\(wy) \(ww)x\(wh) @\(sc)x nat=\(nat)x mir=\(screen.mirrored != nil)")
        }

        lines.append("ext: \(mgr.isConnected ? "ON" : "off") sync=\(mgr.isSyncEnabled)")

        if let win = mgr.externalWindow {
            let wf = win.frame
            lines.append("win: \(Int(wf.width))x\(Int(wf.height))")
        }
        if let wv = mgr.serverState?.handlerContext.webView {
            let bounds = wv.bounds
            lines.append("wv: \(Int(bounds.width))x\(Int(bounds.height)) csf=\(String(format: "%.0f", wv.contentScaleFactor))")
        }

        lines.append("phone: port \(serverState.deviceInfo.port)")
        debugText = lines.joined(separator: "\n")
    }}
