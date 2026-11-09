import AppKit

extension HandlerContext {
    func enter3DInspector(windowId: String? = nil) async throws {
        let target = try visible3DInspectorRenderer(windowId: windowId)
        let snapshot = try? await target.takeSnapshot()
        let image = snapshot?.tiffRepresentation.flatMap { NSBitmapImageRep(data: $0) }?
            .representation(using: .png, properties: [:])?.base64EncodedString()
        _ = try await target.evaluateJS(Snapshot3DBridge.enterScript)
        if let image {
            _ = try? await target.evaluateJS(Snapshot3DBridge.previewScript(image))
        }
    }

    /// The inspector operates on the same live renderer as RendererContainerView.
    /// Restored tab bookkeeping can name a renderer that is not attached to the
    /// visible browser. It must never receive the scene or its preview instead.
    func evaluate3DInspectorJS(_ script: String, windowId: String? = nil) async throws -> Any? {
        try await visible3DInspectorRenderer(windowId: windowId).evaluateJS(script)
    }

    private func visible3DInspectorRenderer(windowId: String?) throws -> any RendererEngine {
        try Task.checkCancellation()
        if let remoteDocumentGuard, !remoteDocumentGuard() { throw CancellationError() }
        guard let renderer else { throw HandlerError.noWebView }
        if let browserControlEngineName, browserControlEngineName != renderer.engineName {
            throw HandlerError.rendererHidden
        }
        if let windowId {
            guard let entry = WindowRegistry.shared.entry(for: windowId) else {
                throw HandlerError.windowNotFound(windowId)
            }
            guard renderer.makeView().window === entry.window else { throw HandlerError.rendererHidden }
        }
        return renderer
    }
}
