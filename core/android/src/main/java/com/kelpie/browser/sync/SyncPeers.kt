package com.kelpie.browser.sync

import java.net.InetAddress

/** Where a discovered peer listens, after the outgoing address rule. */
data class PeerTarget(
    val addresses: List<InetAddress>,
    val port: Int,
)

/**
 * Peers this run knows about: discovered advertisements, handshakes in either
 * role, per-peer backoff and the status shown by `get-cookie-sync-status`.
 */
class SyncPeers(
    private val clock: () -> Long,
) {
    enum class State { DISCOVERED, WAITING, HANDSHAKING, CONNECTED, BACKOFF }

    class Peer internal constructor(
        val replica: String,
    ) {
        var platform: String? = null
        var name: String? = null
        var state = State.DISCOVERED
        var lastSyncAt: Long? = null
        var lastError: String? = null
        var target: PeerTarget? = null
        var seenAt = 0L
        var failures = 0
        var retryAt = 0L
        var sessions = 0
    }

    private val peers = linkedMapOf<String, Peer>()

    @Synchronized fun discovered(
        replica: String,
        target: PeerTarget,
    ): Peer {
        val peer = peers.getOrPut(replica) { Peer(replica).also { it.seenAt = clock() } }
        peer.target = target
        return peer
    }

    /** The advertisement went away. A peer with no live session is forgotten. */
    @Synchronized fun lost(replica: String) {
        val peer = peers[replica] ?: return
        peer.target = null
        if (peer.sessions == 0) peers.remove(replica)
    }

    /**
     * Records what a peer said about itself. Unknown replicas are created only
     * when [create] is set (after a proven session or a discovered advert), so
     * unauthenticated hellos cannot grow the table.
     */
    @Synchronized fun introduced(
        replica: String,
        platform: String?,
        name: String?,
        create: Boolean = false,
    ) {
        val peer = peers[replica] ?: if (create) Peer(replica).also { it.seenAt = clock() }.also { peers[replica] = it } else return
        if (platform != null) peer.platform = platform
        if (name != null) peer.name = name
    }

    @Synchronized fun get(replica: String): Peer? = peers[replica]

    @Synchronized fun advertised(): List<Peer> = peers.values.filter { it.target != null }

    @Synchronized fun state(
        replica: String,
        state: State,
    ) {
        peers[replica]?.state = state
    }

    @Synchronized fun sessionOpened(replica: String) {
        val peer = peers.getOrPut(replica) { Peer(replica).also { it.seenAt = clock() } }
        peer.sessions++
        peer.state = State.CONNECTED
        peer.failures = 0
        peer.retryAt = 0
        peer.lastError = null
    }

    @Synchronized fun sessionClosed(replica: String) {
        val peer = peers[replica] ?: return
        peer.sessions = (peer.sessions - 1).coerceAtLeast(0)
        if (peer.sessions == 0) {
            if (peer.target == null) {
                peers.remove(replica)
            } else if (peer.state == State.CONNECTED) {
                peer.state = State.DISCOVERED
            }
        }
    }

    @Synchronized fun hasSession(replica: String): Boolean = (peers[replica]?.sessions ?: 0) > 0

    @Synchronized fun synced(replica: String) {
        peers[replica]?.lastSyncAt = clock()
    }

    /** Records a failure and returns when the next attempt may start (5 s doubling to 5 min). */
    @Synchronized fun failed(
        replica: String,
        code: String,
    ): Long {
        val peer = peers[replica] ?: return clock() + SyncProtocol.BACKOFF_MIN_MS
        peer.lastError = code
        peer.failures++
        val delay =
            (SyncProtocol.BACKOFF_MIN_MS shl (peer.failures - 1).coerceAtMost(10))
                .coerceAtMost(SyncProtocol.BACKOFF_MAX_MS)
        peer.retryAt = clock() + delay
        if (peer.sessions == 0) peer.state = State.BACKOFF
        return peer.retryAt
    }

    /** A refusal from the other side's hello that is not this peer's fault, shown in status. */
    @Synchronized fun noted(
        replica: String,
        code: String,
    ) {
        peers[replica]?.lastError = code
    }

    /**
     * Peers in the status shape: `handshaking`, `connected`, `backoff`,
     * `clock-skew` or `failed` (a proof or account refusal, still retried).
     */
    @Synchronized fun status(): List<Map<String, Any?>> =
        peers.values.map { peer ->
            buildMap {
                put("replica", peer.replica)
                put("platform", peer.platform.orEmpty())
                put("name", peer.name.orEmpty())
                put("state", publicState(peer))
                peer.lastSyncAt?.let { put("lastSyncAt", it) }
                peer.lastError?.let { put("lastError", it) }
            }
        }

    private fun publicState(peer: Peer): String =
        when {
            peer.sessions > 0 -> "connected"
            peer.lastError == "CLOCK_SKEW" -> "clock-skew"
            peer.state == State.BACKOFF && peer.lastError in PROOF_FAILURES -> "failed"
            peer.state == State.BACKOFF -> "backoff"
            else -> "handshaking"
        }

    private companion object {
        val PROOF_FAILURES = setOf("AUTH_FAILED", "ACCOUNT_MISMATCH")
    }
}
