import Foundation

#if DEBUG
/// Test-only evidence: one mapping is usable only when every sampled frame shares it.
struct IOSG08GeometryEvidence {
    typealias Body = [String: Any]
    private var first: (document: String, viewport: IOSWorkflowTab.Viewport)?
    private var stable = true
    private var samples = 0

    mutating func record(document: String, viewport: IOSWorkflowTab.Viewport) {
        samples += 1
        guard viewport.fixtureDocumentID?.isEmpty == false else { stable = false; return }
        if let first {
            if first.document != document || first.viewport != viewport { stable = false }
        } else {
            first = (document, viewport)
        }
    }

    func manifest(encodedFrames: Int) -> Body? {
        guard stable, let first, let fixtureID = first.viewport.fixtureDocumentID,
              !first.document.isEmpty, encodedFrames > 0, samples >= encodedFrames else { return nil }
        let viewport = first.viewport
        return [
            "kind": "constant-native-content", "nativeDocumentId": first.document, "fixtureDocumentId": fixtureID,
            "stableNativeDocument": true, "fixtureEventsBound": true, "sampledFrames": encodedFrames,
            "nativeBounds": ["width": viewport.bounds.width, "height": viewport.bounds.height],
            "contentRect": ["x": viewport.content.minX, "y": viewport.content.minY,
                            "width": viewport.content.width, "height": viewport.content.height],
            "visualViewport": ["offsetLeft": viewport.visible.minX, "offsetTop": viewport.visible.minY,
                               "width": viewport.visible.width, "height": viewport.visible.height, "scale": viewport.scale]
        ]
    }
}
#endif
