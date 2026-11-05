import Foundation

/// Preserve registered outputs even when Foundation enumerates a resolved temporary path.
enum ScriptCaptureOutputCleanup {
    static func prune(directory: URL, retaining outputs: [URL]) {
        let retained = Set(outputs.map { $0.resolvingSymlinksInPath() })
        for url in (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        where !retained.contains(url.resolvingSymlinksInPath()) {
            try? FileManager.default.removeItem(at: url)
        }
    }
}
