import UIKit
import WebKit

/// Runs cookie sync for the standalone iOS app's default website store while signed in.
/// iOS suspends sockets in the background, so a background transition flushes pending
/// pushes inside a background task and then stops the listener and browsing; returning
/// to the foreground opens a new run (`launch:false`). Embedded sessions never sync.
@MainActor
final class MobileCookieSync {
    static let shared = MobileCookieSync()

    private var service: CookieSyncService?
    private var declined = false
    private var backgroundEpoch = 0
    private var backgroundTask = UIBackgroundTaskIdentifier.invalid

    func start(embedded: Bool) {
        guard service == nil else { return }
        guard KelpieStorage.standalone, !embedded else {
            declined = true
            return
        }
        let source = WebKitSyncCookieSource(store: KelpieWebsiteData.store.httpCookieStore)
        let environment = SyncEnvironment(platform: "ios", deviceName: UIDevice.current.name)
        let created = CookieSyncService(account: UOASyncAccount(), source: source, environment: environment)
        service = created
        created.start()
    }

    func stop() {
        endBackgroundTask()
        service?.stop()
        service = nil
    }

    func enterForeground() {
        backgroundEpoch += 1
        endBackgroundTask()
        service?.setActive(true)
    }

    func enterBackground() {
        guard let service else { return }
        backgroundEpoch += 1
        let epoch = backgroundEpoch
        endBackgroundTask()
        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "Kelpie cookie sync") { [weak self] in
            MainActor.assumeIsolated { self?.finishBackground(epoch) }
        }
        Task { @MainActor [weak self] in
            await service.flush(timeout: 10)
            self?.finishBackground(epoch)
        }
    }

    func status() async -> [String: Any] {
        if let service { return await service.status() }
        var result: [String: Any] = [
            "supported": !declined, "signedIn": UOAAccount.shared.profile != nil, "listening": false,
            "peers": [[String: Any]](), "store": [String: Any]()
        ]
        if declined { result["reason"] = "EMBEDDED_SESSION" }
        return result
    }

    private func finishBackground(_ epoch: Int) {
        guard epoch == backgroundEpoch else { return }
        service?.setActive(false)
        endBackgroundTask()
    }

    private func endBackgroundTask() {
        guard backgroundTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTask)
        backgroundTask = .invalid
    }
}
