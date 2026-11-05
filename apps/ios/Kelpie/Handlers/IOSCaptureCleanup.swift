import Foundation

/// Run directories are private and flat. Compare resolved paths so filesystem aliases
/// cannot cause cleanup to delete a file already registered for download.
enum IOSCaptureCleanup {
    static func prune(directory: URL, retaining: Set<URL>) {
        let manager = FileManager.default
        let retainedPaths = Set(retaining.map { $0.resolvingSymlinksInPath().standardizedFileURL.path })
        let entries = (try? manager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        let discarded = entries.filter { !retainedPaths.contains($0.resolvingSymlinksInPath().standardizedFileURL.path) }
        for entry in discarded { try? manager.removeItem(at: entry) }
        if discarded.count == entries.count { try? manager.removeItem(at: directory) }
    }
}
