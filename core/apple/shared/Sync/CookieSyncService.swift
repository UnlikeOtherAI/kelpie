import Foundation
import Network

/// Peer-to-peer sync of the default cookie store between Kelpies signed in to the same
/// UOA account on one network. See docs/plans/2026-11-09-p2p-cookie-sync.md.
///
/// A run exists while the service is started, active (iOS: foreground) and signed in.
/// Each run opens the store with a fresh replica id, listens, advertises and browses;
/// sign-out, an account change, `stop()` or deactivation tear it down completely.
@MainActor
final class CookieSyncService {
    let account: SyncAccount
    let source: SyncCookieSource
    let environment: SyncEnvironment
    let uoa = SyncAsyncSemaphore(limit: SyncLimits.concurrentUOACalls)
    private(set) var run: SyncRun?
    private(set) var lastError: String?
    private var started = false
    private var active = true
    private var opening: Task<Void, Never>?
    private var openingFence: SyncFence?
    private var closing: Task<Void, Never>?

    init(account: SyncAccount, source: SyncCookieSource, environment: SyncEnvironment) {
        self.account = account
        self.source = source
        self.environment = environment
    }

    var timing: SyncTiming { environment.timing }

    func now() -> Int64 { environment.clock() }

    func start() {
        guard !started else { return }
        started = true
        account.observe { [weak self] in self?.reconcile() }
        reconcile()
    }

    /// Full teardown. Website cookies stay as they are.
    func stop() {
        started = false
        reconcile()
    }

    /// iOS foreground/background. Reactivating opens a new run with `launch:false`.
    func setActive(_ isActive: Bool) {
        active = isActive
        reconcile()
    }

    /// The bound sync port of the current run, once listening.
    var listenerPort: UInt16? { run?.port }

    /// True while `run` is this service's run for the account's live subject and generation.
    func isCurrent(_ run: SyncRun) -> Bool {
        run === self.run && !run.cancelled && account.fence == run.fence
    }

    // MARK: - Lifecycle

    private func reconcile() {
        let wanted = started && active ? account.fence : nil
        if let run, !run.cancelled, run.fence == wanted { return }
        if let openingFence, openingFence == wanted { return }
        teardown()
        if let wanted { open(wanted) }
    }

    private func open(_ fence: SyncFence) {
        let previous = closing
        openingFence = fence
        opening = Task { @MainActor [weak self] in
            await previous?.value
            guard let self, !Task.isCancelled, self.openingFence == fence else { return }
            self.opening = nil
            self.openingFence = nil
            guard self.started, self.active, self.account.fence == fence else { return }
            self.begin(fence)
        }
    }

    private func begin(_ fence: SyncFence) {
        let replica = SyncCrypto.randomText(16)
        let launch = environment.claimLaunch()
        let store: SyncStoreBridge
        do {
            try SyncStoreLocation.prepare(environment.storeURL)
            store = try SyncStoreBridge(
                path: environment.storeURL.path, subject: fence.subject, replica: replica, launch: launch, clock: environment.clock
            )
        } catch {
            lastError = SyncFailure.code(of: error)
            SyncLog.failure("store open", error)
            return
        }
        lastError = nil
        let run = SyncRun(fence: fence, replica: replica, store: store, warming: launch)
        self.run = run
        source.setChangeHandler { [weak self] in self?.cookiesChanged() }
        startListener(run)
        startDiscovery(run)
        if launch { scheduleWarmup(run) } else { scheduleScan(run, after: 0) }
        scheduleHintRefresh(run)
        SyncLog.info("sync run opened (launch: \(launch))")
    }

    private func teardown() {
        opening?.cancel()
        opening = nil
        openingFence = nil
        guard let run else { return }
        self.run = nil
        run.cancel()
        source.setChangeHandler {}
        let store = run.store
        let previous = closing
        closing = Task {
            await previous?.value
            await store.close()
        }
        SyncLog.info("sync run closed")
    }

    // MARK: - Scanning

    func cookiesChanged() {
        guard let run, isCurrent(run) else { return }
        scheduleScan(run, after: timing.scanQuiet)
    }

    /// Scans after `delay` of quiet; a newer change restarts the delay.
    func scheduleScan(_ run: SyncRun, after delay: TimeInterval) {
        run.scanTask?.cancel()
        run.scanTask = Task { @MainActor [weak self] in
            if delay > 0 { try? await Task.sleep(nanoseconds: Self.nanoseconds(delay)) }
            guard !Task.isCancelled, let self, self.isCurrent(run) else { return }
            await self.scan(run)
        }
    }

    func scan(_ run: SyncRun) async {
        do {
            let result = try await run.store.scan(snapshot(run))
            guard isCurrent(run), result["deferred"] as? Bool != true else { return }
            if (result["changed"] as? Int ?? 0) > 0 { feedChanged(run, except: nil) }
        } catch {
            SyncLog.failure("scan", error)
        }
    }

    /// The store has records peers may not have: wake long polls and push.
    func feedChanged(_ run: SyncRun, except source: String?) {
        run.changes.fire()
        for channel in run.initiatorChannels where channel.peer != source { schedulePush(run, channel) }
    }

    func snapshot(_ run: SyncRun) -> SyncStoreBridge.Snapshot {
        { [weak self] in
            guard let self, self.isCurrent(run) else { throw CancellationError() }
            return try await self.source.snapshot()
        }
    }

    /// Engine writes for one merge, abandoned as soon as the run is no longer current.
    func applyOps(_ run: SyncRun) -> SyncStoreBridge.Apply {
        { [weak self] ops in
            guard let self, self.isCurrent(run) else { return nil }
            var results: [SyncCookieOpResult] = []
            for op in ops {
                results.append(await self.source.apply(op))
                guard self.isCurrent(run) else { return nil }
            }
            return results
        }
    }

    // MARK: - Warm-up

    private func scheduleWarmup(_ run: SyncRun) {
        for delay in [timing.warmupMinimum, timing.warmupMaximum] {
            run.spawn { [weak self] in
                try? await Task.sleep(nanoseconds: Self.nanoseconds(delay))
                guard let self, self.isCurrent(run) else { return }
                self.warmupProgress(run, completed: nil)
            }
        }
    }

    /// Peers seen in the first `warmupMinimum` seconds must each deliver a complete feed.
    func noteSeen(_ run: SyncRun, _ replica: String) {
        guard run.warming, Date().timeIntervalSince(run.launchedAt) < timing.warmupMinimum else { return }
        run.warmupPeers.insert(replica)
    }

    /// Ends warm-up after a complete feed from every early peer (no sooner than
    /// `warmupMinimum`), or at `warmupMaximum`, then runs the first scan.
    func warmupProgress(_ run: SyncRun, completed replica: String?) {
        guard run.warming else { return }
        if let replica { run.warmupDone.insert(replica) }
        let elapsed = Date().timeIntervalSince(run.launchedAt)
        let everyPeer = run.warmupPeers.isSubset(of: run.warmupDone)
        guard elapsed >= timing.warmupMaximum || (elapsed >= timing.warmupMinimum && everyPeer) else { return }
        run.warming = false
        run.spawn { [weak self] in
            await run.store.finishWarmup()
            guard let self, self.isCurrent(run) else { return }
            await self.scan(run)
        }
    }

    // MARK: - Advertising

    func acceptedHints(_ run: SyncRun) -> Set<String> {
        (try? SyncStoreBridge.accountHints(subject: run.fence.subject, now: now()).accepted) ?? []
    }

    private func service(_ run: SyncRun) -> NWListener.Service? {
        guard let hint = try? SyncStoreBridge.accountHints(subject: run.fence.subject, now: now()).current else { return nil }
        return NWListener.Service(
            name: run.replica,
            type: SyncListener.serviceType,
            domain: nil,
            txtRecord: NWTXTRecord(["v": "1", "id": run.replica, "h": hint])
        )
    }

    private func startListener(_ run: SyncRun) {
        let listener = SyncListener(
            rule: environment.rule,
            admit: { [weak self] route, head, source in
                await self?.admit(route, head, source: source, run: run) ?? .reject(.error(503, "UNAVAILABLE"))
            },
            handle: { [weak self] route, head, body, source in
                await self?.handle(route, head, body: body, source: source, run: run) ?? .error(503, "UNAVAILABLE")
            }
        )
        run.listener = listener
        listener.start(service: environment.advertise ? service(run) : nil) { [weak self] port in
            Task { @MainActor in
                guard let self, self.isCurrent(run) else { return }
                run.port = port
            }
        }
    }

    private func startDiscovery(_ run: SyncRun) {
        let context = SyncDiscoveryContext(ownReplica: run.replica, rule: environment.rule) { [weak self] in
            self?.acceptedHints(run) ?? []
        }
        let discovery = environment.makeDiscovery(context)
        run.discovery = discovery
        discovery.start { [weak self] adverts in self?.discoveryChanged(run, adverts) }
    }

    /// The advertisement carries today's hint; refresh it when the UTC date changes.
    private func scheduleHintRefresh(_ run: SyncRun) {
        let day: Int64 = 86_400_000
        let current = now()
        let next = (current / day + 1) * day + 1_000
        run.spawn { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(max(0, next - current)) * 1_000_000)
            guard let self, self.isCurrent(run) else { return }
            if self.environment.advertise { run.listener?.setService(self.service(run)) }
            run.discovery?.refresh()
            self.scheduleHintRefresh(run)
        }
    }

    // MARK: - Status and flush

    /// `{supported, signedIn, replica?, listening, peers, store, lastError?}`; counts only.
    func status() async -> [String: Any] {
        var result: [String: Any] = [
            "supported": true, "signedIn": account.fence != nil, "listening": run?.port != nil, "peers": [[String: Any]]()
        ]
        if let lastError { result["lastError"] = lastError }
        guard let run, isCurrent(run) else {
            result["store"] = [String: Any]()
            return result
        }
        result["replica"] = run.replica
        result["peers"] = peerStatus(run)
        var counts = (try? await run.store.status()) ?? [:]
        counts.removeValue(forKey: "replica")
        result["store"] = counts
        return result
    }

    private func peerStatus(_ run: SyncRun) -> [[String: Any]] {
        run.peers.values.sorted { $0.replica < $1.replica }.map { peer in
            var entry: [String: Any] = [
                "replica": peer.replica, "platform": peer.platform, "name": peer.name, "state": state(of: peer, in: run).rawValue
            ]
            if let lastSyncAt = peer.lastSyncAt { entry["lastSyncAt"] = lastSyncAt }
            if let lastError = peer.lastError { entry["lastError"] = lastError }
            return entry
        }
    }

    private func state(of peer: SyncPeer, in run: SyncRun) -> SyncPeer.State {
        if run.channel(for: peer.replica) != nil { return .connected }
        if peer.handshaking { return .connecting }
        if let retryAt = peer.retryAt, retryAt > Date() { return .retrying }
        return peer.advert == nil ? .offline : .waiting
    }

    /// Scans now and sends pending changes to every peer, for at most `timeout` seconds.
    /// iOS calls this in a background task before deactivating.
    func flush(timeout: TimeInterval) async {
        guard let run, isCurrent(run) else { return }
        run.scanTask?.cancel()
        let deadline = Date().addingTimeInterval(timeout)
        await scan(run)
        for channel in run.initiatorChannels { schedulePush(run, channel) }
        // Let long polls woken by the scan pick up their records before counting them.
        try? await Task.sleep(nanoseconds: 100_000_000)
        while isCurrent(run), Date() < deadline,
              run.answering > 0 || run.initiatorChannels.contains(where: \.pushing) {
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
    }

    static func nanoseconds(_ seconds: TimeInterval) -> UInt64 { UInt64(max(0, seconds) * 1_000_000_000) }
}
