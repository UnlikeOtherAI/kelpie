import Foundation

/// The default store moving to another engine (the macOS renderer switch). The outgoing
/// engine is scanned first so no local edit is lost; the incoming engine is then adopted
/// with a rebase, so cookies it normalises, refuses or already holds never reach peers as
/// new versions or deletions.
extension CookieSyncService {
    func storeWillSwitch() async {
        guard let run, isCurrent(run) else { return }
        run.scanTask?.cancel()
        await scan(run)
        guard isCurrent(run) else { return }
        run.switchingStore = true
    }

    func storeDidSwitch() async {
        guard let run, isCurrent(run) else { return }
        defer { run.switchingStore = false }
        run.scanTask?.cancel()
        do {
            let result = try await run.store.rebase(snapshot(run))
            guard isCurrent(run) else { return }
            if (result["adopted"] as? Int ?? 0) > 0 { feedChanged(run, except: nil) }
        } catch {
            SyncLog.failure("rebase", error)
        }
    }
}
