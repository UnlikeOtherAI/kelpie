import WebKit

extension HandlerContext {
    func enter3DInspector() async throws {
        guard let webView else { throw HandlerError.noWebView }
        let config = WKSnapshotConfiguration()
        config.rect = webView.bounds
        config.snapshotWidth = 320
        let snapshot = try? await webView.takeSnapshot(configuration: config)
        _ = try await evaluateJS(Snapshot3DBridge.enterScript)
        if let image = snapshot?.pngData()?.base64EncodedString() {
            _ = try? await evaluateJS(Snapshot3DBridge.previewScript(image))
        }
    }
}
