import Foundation

/// Bridge exposing the 3D-inspector JavaScript to Swift callers.
///
/// The enter and exit scripts live as standalone JS sources under
/// `Resources/Snapshot3D/`. The enter script is assembled at first access
/// from scene and tool phase files so each individual
/// source file stays within the project's 500-line limit. The phases share
/// closure state inside one IIFE, so the concatenation is what runs.
///
/// The small runtime-control scripts (mode/zoom/reset) stay inline because
/// they take Swift-side arguments.
enum Snapshot3DBridge {

    private static let enterResult = Result {
        try ["enter-setup", "enter-collect", "enter-apply", "enter-scene",
             "enter-tree", "enter-tools", "enter-input"]
            .map { try loadResource(named: $0) }
            .joined(separator: "\n")
    }

    static var enterScript: String {
        get throws { try enterResult.get() }
    }

    private static let exitResult = Result { try loadResource(named: "exit") }

    static var exitScript: String {
        get throws { try exitResult.get() }
    }

    static func setModeScript(_ mode: String) -> String {
        """
        (function() {
            if (!window.__m3d || typeof window.__m3d.setMode !== 'function') return null;
            return window.__m3d.setMode('\(JSEscape.string(mode))');
        })();
        """
    }

    static func previewScript(_ image: String) -> String {
        "window.__m3d?.setPreview('data:image/png;base64,\(JSEscape.string(image))');"
    }

    static let resetViewScript = #"""
    (function() {
        if (!window.__m3d || typeof window.__m3d.resetView !== 'function') return false;
        return window.__m3d.resetView();
    })();
    """#

    static func zoomByScript(_ delta: Double) -> String {
        """
        (function() {
            if (!window.__m3d || typeof window.__m3d.zoomBy !== 'function') return null;
            return window.__m3d.zoomBy(\(delta));
        })();
        """
    }

    /// Xcode flattens globbed resources into the bundle root. Also accept
    /// directory-preserving bundles. Packaging errors must not terminate the app.
    static func loadResource(named name: String, bundle: Bundle = KelpieResources.bundle) throws -> String {
        let url = bundle.url(forResource: name, withExtension: "js", subdirectory: "Snapshot3D")
            ?? bundle.url(forResource: name, withExtension: "js")
        guard let url else {
            throw CocoaError(.fileNoSuchFile, userInfo: [
                NSFilePathErrorKey: "Snapshot3D/\(name).js"
            ])
        }
        return try String(contentsOf: url, encoding: .utf8)
    }
}
