package com.kelpie.browser.sync

import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.cancelAndJoin
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Semaphore
import java.io.File
import java.security.SecureRandom
import java.util.concurrent.ConcurrentHashMap

/** Scan cadence, warm-up windows and the fallback-initiator delay; tests shorten them. */
data class SyncTimings(
    val pageLoadQuietMs: Long = 1_000L,
    val recentScanMs: Long = 15_000L,
    val fullScanMs: Long = 5 * 60_000L,
    val retryOpenMs: Long = 30_000L,
    val warmupPeerWindowMs: Long = SyncProtocol.WARMUP_PEER_WINDOW_MS,
    val warmupMaxMs: Long = SyncProtocol.WARMUP_MAX_MS,
    val fallbackInitiateMs: Long = SyncProtocol.FALLBACK_INITIATE_MS,
)

/**
 * Peer-to-peer cookie sync for the default store while the person is signed in.
 * Opens the store, listener, advertisement and browser on sign-in, and tears all
 * of them down on sign-out or account change. Each sign-in is a [SyncRun]; every
 * timer and handshake belongs to that run's scope and checks it is still current.
 */
class CookieSyncService(
    private val account: SyncAccount,
    private val cookies: CookieSource,
    private val directory: File,
    private val discovery: SyncDiscovery,
    subnets: SyncSubnets,
    private val transport: SyncTransport,
    private val deviceName: String,
    private val recent: RecentLoads,
    private val launches: SyncLaunches = SyncLaunches.process,
    private val clock: () -> Long = System::currentTimeMillis,
    private val random: SecureRandom = SecureRandom(),
    private val timings: SyncTimings = SyncTimings(),
    private val log: SyncLog = SyncLog.none,
) {
    private class Active(
        val run: SyncRun,
        val responder: SyncResponder,
        val listener: SyncListener,
        val scope: CoroutineScope,
        val port: Int,
    ) {
        val connectors = ConcurrentHashMap<String, Job>()
        val pendingHosts = ConcurrentHashMap<String, Job>()
    }

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
    private val accountPermits = Semaphore(SyncProtocol.MAX_UOA_CALLS)
    private val addresses = SyncAddressRule(subnets)
    private val outgoing = SyncRateLimiter(clock, perKey = Int.MAX_VALUE, total = SyncProtocol.OUTGOING_HANDSHAKES_PER_MIN)

    @Volatile private var active: Active? = null
    private var watcher: Job? = null

    /** Follows the account: sign-in opens a run, sign-out or a new account closes it. */
    fun start() {
        if (watcher != null) return
        // collect is sequential, so one identity change is handled completely before the next.
        watcher =
            scope.launch {
                account.identity.collect { identity ->
                    if (active?.run?.identity == identity) return@collect
                    teardown()
                    if (identity != null) openWithRetry(identity)
                }
            }
    }

    suspend fun stop() {
        watcher?.cancelAndJoin()
        watcher = null
        teardown()
    }

    /** A page in an unpartitioned tab finished loading; scan its host after 1 s of quiet. */
    fun pageLoaded(
        host: String,
        url: String,
    ) {
        recent.record(host, url)
        val current = active ?: return
        current.pendingHosts.remove(host)?.cancel()
        current.pendingHosts[host] =
            current.scope.launch {
                delay(timings.pageLoadQuietMs)
                current.pendingHosts.remove(host)
                scanQuietly(current.run, setOf(host))
            }
    }

    /** Scans now; [hosts] limits the read. Returns changed entries, or null when not running. */
    suspend fun scan(hosts: Set<String>? = null): Long? = active?.run?.let { runCatching { it.scan(hosts) }.getOrNull() }

    /** Metadata entry locations of the running store (empty when not running). */
    suspend fun entryLocations(): List<EntryLocation> =
        active
            ?.run
            ?.store
            ?.let { store -> runCatching { store.use { entries() } }.getOrNull() }
            .orEmpty()

    suspend fun status(): Map<String, Any?> {
        val current = active
        val store = current?.run?.let { runCatching { it.storeStatus() }.getOrNull() }
        return buildMap {
            put("signedIn", account.identity.value != null)
            current?.let { put("replica", it.run.replica) }
            put("listening", current != null)
            put(
                "peers",
                current
                    ?.run
                    ?.peers
                    ?.status()
                    .orEmpty(),
            )
            put("store", store?.let { SyncMaps.fromJson(it) as Map<*, *> }?.filterKeys { it != "replica" }.orEmpty())
        }
    }

    // --- Lifecycle ------------------------------------------------------------

    private suspend fun openWithRetry(identity: SyncIdentity) {
        while (account.identity.value == identity) {
            try {
                open(identity)
                return
            } catch (error: Exception) {
                val code = (error as? SyncFailure)?.code ?: error.javaClass.simpleName
                log.log(SyncLog.WARN, "cookie sync could not start ($code)")
            }
            delay(timings.retryOpenMs)
        }
    }

    private suspend fun open(identity: SyncIdentity) {
        val replica = SyncBase64.encode(ByteArray(16).also(random::nextBytes))
        val launch = launches.pending
        val now = clock()
        val store = SyncStore.open(directory, identity.subject, replica, launch, now)
        launches.consumed()
        val run =
            SyncRun(
                identity,
                store,
                cookies,
                account,
                accountPermits,
                deviceName,
                clock,
                random,
                SyncRun.Warmup(now, launch, timings.warmupPeerWindowMs, timings.warmupMaxMs),
            )
        val responder = SyncResponder(run)
        val listener = SyncListener(responder, addresses, clock)
        val port =
            try {
                listener.start()
            } catch (error: Throwable) {
                // Includes cancellation by stop(): never leave a store or socket open.
                run.close()
                runCatching { listener.stop() }
                kotlinx.coroutines.withContext(kotlinx.coroutines.NonCancellable) { store.close() }
                throw error
            }
        val runScope = CoroutineScope(scope.coroutineContext + SupervisorJob(scope.coroutineContext[Job]))
        val current = Active(run, responder, listener, runScope, port)
        active = current
        discovery.start(SyncDiscovery.Advert(replica, run.hints().first, port), peerListener(current))
        runScope.launch { warmupLoop(current) }
        runScope.launch { advertLoop(current) }
        runScope.launch { every(timings.recentScanMs) { recent.hosts().takeIf { it.isNotEmpty() }?.let { scanQuietly(run, it) } } }
        runScope.launch { every(timings.fullScanMs) { scanQuietly(run, null) } }
        if (!launch) runScope.launch { scanQuietly(run, null) }
        log.log(SyncLog.INFO, "cookie sync started (launch=$launch)")
    }

    private suspend fun teardown() {
        val current = active ?: return
        active = null
        current.run.close()
        current.scope.cancel()
        runCatching { discovery.stop() }
        runCatching { current.listener.stop() }
        current.responder.closeAll()
        runCatching { current.run.store.close() }
        log.log(SyncLog.INFO, "cookie sync stopped")
    }

    // --- Timers -----------------------------------------------------------------

    private suspend fun warmupLoop(current: Active) {
        if (!current.run.warmup.launch) return
        while (!current.run.warmupDue()) delay(WARMUP_TICK_MS)
        current.run.store.use { finishWarmup() }
        // The first scan after launch: missing entries are dropped, unknown cookies get the zero version.
        scanQuietly(current.run, null)
        current.run.wake()
    }

    private suspend fun advertLoop(current: Active) {
        var hint = current.run.hints().first
        while (true) {
            delay(ADVERT_TICK_MS)
            val next = current.run.hints().first
            if (next != hint) {
                hint = next
                runCatching { discovery.update(SyncDiscovery.Advert(current.run.replica, hint, current.port)) }
            }
        }
    }

    private suspend fun every(
        intervalMs: Long,
        action: suspend () -> Unit,
    ) {
        while (true) {
            delay(intervalMs)
            action()
        }
    }

    private suspend fun scanQuietly(
        run: SyncRun,
        hosts: Set<String>?,
    ) {
        try {
            run.scan(hosts)
        } catch (failure: SyncFailure) {
            if (failure.code != "STALE") log.log(SyncLog.WARN, "cookie scan failed (${failure.code})")
        }
    }

    // --- Peers ----------------------------------------------------------------

    private fun peerListener(current: Active) =
        object : SyncDiscovery.Listener {
            override fun found(peer: SyncDiscovery.Found) {
                val run = current.run
                if (!run.isCurrent() || peer.replica == run.replica) return
                if (peer.hint !in run.hints().second) return
                val targets = addresses.outgoing(peer.addresses)
                if (targets.isEmpty()) return
                run.peers.discovered(peer.replica, PeerTarget(targets, peer.port))
                run.peerSeen(peer.replica)
                current.connectors.computeIfAbsent(peer.replica) {
                    current.scope.launch {
                        try {
                            connect(current, peer.replica)
                        } finally {
                            current.connectors.remove(peer.replica)
                        }
                    }
                }
            }

            override fun lost(replica: String) {
                current.run.peers.lost(replica)
            }
        }

    /**
     * The smaller replica id initiates. The other side waits 15 s for the peer's
     * session and initiates itself only when none formed (a blocked listener).
     */
    private suspend fun connect(
        current: Active,
        replica: String,
    ) {
        val run = current.run
        val initiator = SyncInitiator(run, transport)
        val first = run.replica < replica
        while (current.scope.isActive && run.isCurrent()) {
            val peer = run.peers.get(replica) ?: return
            val target = peer.target ?: return
            if (!first) {
                val waitFor = peer.seenAt + timings.fallbackInitiateMs - clock()
                if (waitFor > 0 || current.responder.servedWithin(replica, timings.fallbackInitiateMs)) {
                    if (!run.peers.hasSession(replica)) run.peers.state(replica, SyncPeers.State.WAITING)
                    delay(waitFor.coerceAtLeast(timings.fallbackInitiateMs))
                    continue
                }
            }
            val backoff = peer.retryAt - clock()
            if (backoff > 0) {
                delay(backoff)
                continue
            }
            if (!outgoing.tryAcquire(OUTGOING_KEY)) {
                delay((outgoing.nextSlotAt() - clock()).coerceAtLeast(1_000L))
                continue
            }
            handshakeAndServe(run, initiator, replica, target)
        }
    }

    private suspend fun handshakeAndServe(
        run: SyncRun,
        initiator: SyncInitiator,
        replica: String,
        target: PeerTarget,
    ) {
        run.peers.state(replica, SyncPeers.State.HANDSHAKING)
        val session =
            try {
                initiator.handshake(replica, target)
            } catch (failure: SyncFailure) {
                if (failure.code != "STALE") run.peers.failed(replica, failure.code)
                return
            }
        run.peers.sessionOpened(replica)
        try {
            initiator.serve(session)
        } catch (failure: SyncFailure) {
            // An unknown or expired session means handshake again; anything else backs off.
            if (failure.code != "SYNC_SESSION" && failure.code != "STALE") run.peers.failed(replica, failure.code)
        } finally {
            run.peers.sessionClosed(replica)
        }
    }

    private companion object {
        const val WARMUP_TICK_MS = 500L
        const val ADVERT_TICK_MS = 60_000L
        const val OUTGOING_KEY = "all"
    }
}
