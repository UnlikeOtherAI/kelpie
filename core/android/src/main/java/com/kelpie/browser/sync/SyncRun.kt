package com.kelpie.browser.sync

import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.sync.Semaphore
import kotlinx.coroutines.sync.withPermit
import kotlinx.coroutines.withTimeoutOrNull
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import java.security.SecureRandom

/**
 * One signed-in run of the sync service: one account identity, one open store,
 * one replica id. Every effect re-checks [isCurrent]; work from an old run is
 * discarded once the account changes or the run is closed.
 */
class SyncRun(
    val identity: SyncIdentity,
    val store: SyncStore,
    private val cookies: CookieSource,
    private val account: SyncAccount,
    private val accountPermits: Semaphore,
    val deviceName: String,
    val clock: () -> Long,
    val random: SecureRandom,
    val warmup: Warmup,
) {
    val replica: String get() = store.replica
    val peers = SyncPeers(clock)

    @Volatile var active = true
        private set

    private val feedVersion = MutableStateFlow(0L)

    /** Bumped whenever the store head moves: new local or merged records to send. */
    val feed: StateFlow<Long> = feedVersion
    private var lastHead = 0L

    fun isCurrent(): Boolean = active && account.identity.value == identity

    fun requireCurrent() {
        if (!isCurrent()) throw SyncFailure("STALE", "account changed")
    }

    fun close() {
        active = false
    }

    fun hints(): Pair<String, Set<String>> = SyncCore.hints(identity.subject, clock())

    suspend fun issueTicket(
        challenge: String,
        clientId: String,
    ): String {
        requireCurrent()
        val ticket = accountPermits.withPermit { account.issueTicket(identity, challenge, clientId) }
        requireCurrent()
        return ticket
    }

    suspend fun validateTicket(
        ticket: String,
        challenge: String,
        clientId: String,
    ): Boolean {
        requireCurrent()
        val valid = accountPermits.withPermit { account.validateTicket(identity, ticket, challenge, clientId) }
        requireCurrent()
        return valid
    }

    // --- Store operations -------------------------------------------------

    /** Scans the default store; [hosts] limits the read. Returns the number of changed entries. */
    suspend fun scan(hosts: Set<String>? = null): Long {
        requireCurrent()
        val result =
            store.use {
                if (!isCurrent()) throw SyncFailure("STALE", "account changed")
                scan(cookies.snapshot(entries(), hosts), clock())
            }
        noteHead(result.long("head"))
        return result.long("changed") ?: 0
    }

    /** Answers a pull, holding it until a change or `wait` runs out when nothing is pending. */
    suspend fun answerPull(pull: JsonObject): JsonObject {
        val wait = (pull.long("wait") ?: 0).coerceIn(0, SyncProtocol.MAX_WAIT_MS)
        val deadline = clock() + wait
        while (true) {
            requireCurrent()
            val version = feedVersion.value
            val response = store.use { answerPull(pull, cookies.snapshot(entries(), discover = false), clock()) }
            noteHead(response.long("head"))
            val idle = response.array("records").isNullOrEmpty() && response.bool("more") != true
            val remaining = deadline - clock()
            if (!idle || response.bool("warming") == true || remaining <= 0) return response
            withTimeoutOrNull(remaining) { feedVersion.first { it != version } } ?: return response
        }
    }

    /** Merges one push from the initiator and returns what this store now holds from it. */
    suspend fun acceptPush(push: JsonObject): JsonObject {
        val from = push.string("replica") ?: throw SyncFailure("INVALID_MESSAGE", "push needs replica")
        merge(push.array("records") ?: JsonArray(emptyList()), cursor(from, push.long("seq") ?: 0))
        if (push.bool("more") != true) completedFrom(from)
        val watermark = store.use { watermark(from) }
        return buildJsonObject { put("yourWatermark", watermark) }
    }

    /** Commits one pull page from [peerReplica]. */
    suspend fun commitPull(response: JsonObject) {
        val from = response.string("replica") ?: throw SyncFailure("INVALID_MESSAGE", "pull response needs replica")
        merge(response.array("records") ?: JsonArray(emptyList()), cursor(from, response.long("seq") ?: 0))
    }

    suspend fun buildPush(watermark: JsonObject): JsonObject? {
        requireCurrent()
        // build_push scans first; read the head in the same turn so other peers hear of local changes.
        val (built, head) = store.use { buildPush(watermark, cookies.snapshot(entries(), discover = false), clock()) to status().long("head") }
        noteHead(head)
        return built.obj("push")
    }

    suspend fun watermark(peerReplica: String): JsonObject = store.use { watermark(peerReplica) }

    suspend fun storeStatus(): JsonObject = store.use { status() }

    private suspend fun merge(
        records: JsonArray,
        source: JsonObject,
    ) {
        requireCurrent()
        val outcome = store.use { merge(records, source, clock(), cookies, ::isCurrent) }
        noteHead(outcome.head)
    }

    private fun cursor(
        replica: String,
        seq: Long,
    ) = buildJsonObject {
        put("replica", replica)
        put("seq", seq)
    }

    @Synchronized private fun noteHead(head: Long?) {
        if (head != null && head > lastHead) {
            lastHead = head
            feedVersion.value = feedVersion.value + 1
        }
    }

    /** Wakes pushes and held pulls without a head change (for example when warm-up ends). */
    fun wake() {
        feedVersion.value = feedVersion.value + 1
    }

    // --- Warm-up ------------------------------------------------------------

    /** Records a peer seen while warming; only peers seen in the first window count. */
    fun peerSeen(peerReplica: String) = warmup.seen(peerReplica, clock())

    /** A complete pull from (or full push by) [peerReplica] has been committed. */
    fun completedFrom(peerReplica: String) = warmup.completed(peerReplica)

    /** True once warm-up should end: every early peer is complete after the window, or the maximum passed. */
    fun warmupDue(): Boolean = warmup.launch && warmup.due(clock())

    /**
     * Launch warm-up: it ends after a complete pull from every peer seen in the
     * first [peerWindowMs] (15 s), or after [maxMs] (30 s), whichever is first.
     */
    class Warmup(
        private val startedAt: Long,
        val launch: Boolean,
        private val peerWindowMs: Long,
        private val maxMs: Long,
    ) {
        private val early = mutableSetOf<String>()
        private val complete = mutableSetOf<String>()

        @Synchronized fun seen(
            replica: String,
            now: Long,
        ) {
            if (now - startedAt <= peerWindowMs) early.add(replica)
        }

        @Synchronized fun completed(replica: String) {
            complete.add(replica)
        }

        @Synchronized fun due(now: Long): Boolean {
            val elapsed = now - startedAt
            return elapsed >= maxMs || (elapsed >= peerWindowMs && complete.containsAll(early))
        }
    }
}
