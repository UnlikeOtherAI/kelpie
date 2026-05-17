import Foundation

/// Bridge exposing the 3D-inspector JavaScript to Swift callers.
///
/// The enter and exit scripts live as standalone JS sources under
/// `Resources/Snapshot3D/`. The enter script is assembled at first access
/// from four phase files (setup, collect, apply, input) so each individual
/// source file stays within the project's 500-line limit. The phases share
/// closure state inside one IIFE, so the concatenation is what runs.
///
/// The small runtime-control scripts (mode/zoom/reset) stay inline because
/// they take Swift-side arguments.
enum Snapshot3DBridge {

    static let enterScript: String = [
        "enter-setup",
        "enter-collect",
        "enter-apply",
        "enter-input"
    ]
    .map(loadResource(named:))
    .joined()

    static let exitScript: String = loadResource(named: "exit")

    static func setModeScript(_ mode: String) -> String {
        """
        (function() {
            if (!window.__m3d || typeof window.__m3d.setMode !== 'function') return null;
            return window.__m3d.setMode('\(JSEscape.string(mode))');
        })();
        """
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

    /// Load a bundled JS resource from `Resources/Snapshot3D/<name>.js`.
    ///
    /// The script is part of the app bundle; if the resource is missing the
    /// bundle is broken and the inspector cannot run. Trap loudly rather than
    /// silently returning an empty script.
    private static func loadResource(named name: String) -> String {
        guard let url = Bundle.main.url(
            forResource: name,
            withExtension: "js",
            subdirectory: "Snapshot3D"
        ) else {
            fatalError("Snapshot3DBridge: missing resource Snapshot3D/\(name).js in bundle")
        }
        do {
            return try String(contentsOf: url, encoding: .utf8)
        } catch {
            fatalError("Snapshot3DBridge: failed to read Snapshot3D/\(name).js: \(error)")
        }
    }
}
