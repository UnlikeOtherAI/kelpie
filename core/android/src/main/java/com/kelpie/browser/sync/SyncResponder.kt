package com.kelpie.browser.sync

import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import java.util.concurrent.ConcurrentHashMap

/** An HTTP status and JSON body. */
data class SyncReply(
    val status: Int,
    val body: JsonObject,
)

/**
 * The listener side of the handshake and exchange, independent of the HTTP
 * server. Pending handshakes live 60 s, at most 8 at once; the first `/auth`
 * for a handshake consumes it whatever the outcome; sessions last 10 minutes.
 */
class SyncResponder(
    private val run: SyncRun,
) {
    private class Pending(
        val id: String,
        val peer: HelloSide,
        val platform: String,
        val name: String,
        val own: SyncKeyPair,
        val challenge: String,
        val expiresAt: Long,
    )

    class Session internal constructor(
        val id: String,
        val peerReplica: String,
        internal val keys: SyncSessionKeys,
        val expiresAt: Long,
    ) {
        internal val window = ReplayWindow()
    }

    private val pending = LinkedHashMap<String, Pending>()
    private val sessions = ConcurrentHashMap<String, Session>()
    private val lastServed = ConcurrentHashMap<String, Long>()

    suspend fun hello(body: JsonObject): SyncReply {
        SyncCore.invalid("hello", body)?.let { return refuse(400, "INVALID_MESSAGE") }
        SyncCrypto.decodePublicKey(body.string("key")!!) ?: return refuse(400, "INVALID_MESSAGE")
        val peer = HelloSide(body.string("replica")!!, body.string("key")!!, body.string("nonce")!!)
        if (peer.replica == run.replica) return refuse(400, "INVALID_MESSAGE")
        val now = run.clock()
        if (body.string("hint") !in run.hints().second) return refuse(409, "ACCOUNT_MISMATCH")
        val platform = body.string("platform")!!
        val name = body.string("name")!!
        run.peers.introduced(peer.replica, platform, name)
        if (!SyncProtocol.withinSkew(body.long("now")!!, now)) {
            run.peers.failed(peer.replica, "CLOCK_SKEW")
            return refuse(409, "CLOCK_SKEW")
        }
        run.requireCurrent()
        val own = SyncCrypto.generateKeyPair(run.random)
        val nonce = randomField(32)
        val id = randomField(32)
        val challenge = SyncCore.challenge(peer, HelloSide(run.replica, own.encodedPublicKey, nonce))
        val expiresAt = now + SyncProtocol.PENDING_TTL_MS
        synchronized(pending) {
            pending.values.removeAll { it.expiresAt <= now }
            while (pending.size >= SyncProtocol.MAX_PENDING) pending.remove(pending.keys.first())
            pending[id] = Pending(id, peer, platform, name, own, challenge, expiresAt)
        }
        if (!run.peers.hasSession(peer.replica)) run.peers.state(peer.replica, SyncPeers.State.HANDSHAKING)
        return SyncReply(
            200,
            buildJsonObject {
                put("v", SyncProtocol.VERSION)
                put("replica", run.replica)
                put("now", now)
                put("platform", SyncProtocol.PLATFORM)
                put("name", run.deviceName)
                put("key", own.encodedPublicKey)
                put("nonce", nonce)
                put("handshakeId", id)
                put("expiresAt", expiresAt)
            },
        )
    }

    suspend fun auth(body: JsonObject): SyncReply {
        SyncCore.invalid("auth", body)?.let { return refuse(400, "INVALID_MESSAGE") }
        val id = body.string("handshakeId")!!
        val handshake = synchronized(pending) { pending.remove(id) } ?: return refuse(401, "SYNC_SESSION")
        if (handshake.expiresAt <= run.clock()) return refuse(401, "SYNC_SESSION")
        val peerKey = SyncCrypto.decodePublicKey(handshake.peer.key) ?: return refuse(401, "SYNC_SESSION")
        val initiatorClient = SyncProtocol.initiatorClientId(handshake.peer.replica)
        val valid =
            try {
                run.validateTicket(body.string("ticket")!!, handshake.challenge, initiatorClient)
            } catch (failure: SyncFailure) {
                run.peers.noted(handshake.peer.replica, failure.code)
                return refuse(503, "UOA_UNAVAILABLE")
            }
        if (!valid) {
            run.peers.failed(handshake.peer.replica, "AUTH_FAILED")
            return refuse(403, "AUTH_FAILED")
        }
        val ticket =
            try {
                run.issueTicket(handshake.challenge, SyncProtocol.responderClientId(run.replica))
            } catch (failure: SyncFailure) {
                run.peers.noted(handshake.peer.replica, failure.code)
                return refuse(503, "UOA_UNAVAILABLE")
            }
        run.requireCurrent()
        val keys = SyncChannel.deriveKeys(handshake.own.privateKey, peerKey, handshake.challenge)
        val expiresAt = run.clock() + SyncProtocol.SESSION_MS
        // One session per pair: a new handshake from the same replica replaces the old session.
        sessions.values.filter { it.peerReplica == handshake.peer.replica }.forEach { close(it) }
        sessions[id] = Session(id, handshake.peer.replica, keys, expiresAt)
        run.peers.introduced(handshake.peer.replica, handshake.platform, handshake.name, create = true)
        run.peers.sessionOpened(handshake.peer.replica)
        return SyncReply(
            200,
            buildJsonObject {
                put("ticket", ticket)
                put("sessionExpiresAt", expiresAt)
            },
        )
    }

    /** A live session for the `X-Kelpie-Sync-Session` header; checked before the body is read. */
    fun session(id: String?): Session? {
        val session = id?.let { sessions[it] } ?: return null
        if (session.expiresAt <= run.clock()) {
            close(session)
            return null
        }
        return session
    }

    /** The session is still installed under its id, unexpired, for the current account. */
    private fun live(session: Session): Boolean = session(session.id) === session && run.isCurrent()

    suspend fun exchange(
        session: Session,
        body: JsonObject,
    ): SyncReply {
        // The body may have arrived after expiry or replacement; re-check before using the keys.
        if (!live(session)) return refuse(401, "SYNC_SESSION")
        SyncCore.invalid("exchange", body)?.let { return refuse(400, "INVALID_MESSAGE") }
        val seq = body.long("seq") ?: return refuse(400, "INVALID_MESSAGE")
        val plaintext =
            SyncChannel.open(session.keys.i2r, session.id, SyncChannel.REQUEST, seq, body.string("box")!!)
                ?: return refuse(400, "INVALID_MESSAGE")
        if (!session.window.accept(seq)) return refuse(400, "INVALID_MESSAGE")
        val message = SyncJson.parseObject(plaintext) ?: return refuse(400, "INVALID_MESSAGE")
        if (message.string("replica") != session.peerReplica) return refuse(400, "INVALID_MESSAGE")
        val response =
            try {
                when (message.string("op")) {
                    "pull" -> run.answerPull(message)
                    "push" -> run.acceptPush(message)
                    else -> return refuse(400, "INVALID_MESSAGE")
                }
            } catch (failure: SyncFailure) {
                return if (failure.code == "INVALID_MESSAGE") refuse(400, "INVALID_MESSAGE") else refuse(503, "UNAVAILABLE")
            }
        if (!live(session)) return refuse(401, "SYNC_SESSION")
        run.peers.synced(session.peerReplica)
        lastServed[session.peerReplica] = run.clock()
        val box = SyncChannel.seal(session.keys.r2i, session.id, SyncChannel.RESPONSE, seq, response.toString())
        return SyncReply(
            200,
            buildJsonObject {
                put("seq", seq)
                put("box", box)
            },
        )
    }

    /** True while [replica] holds a live session here or used one within [withinMs]. */
    fun servedWithin(
        replica: String,
        withinMs: Long,
    ): Boolean {
        val now = run.clock()
        if (sessions.values.any { it.peerReplica == replica && it.expiresAt > now }) return true
        return (lastServed[replica] ?: Long.MIN_VALUE / 2) >= now - withinMs
    }

    fun closeAll() {
        sessions.values.toList().forEach { close(it) }
        synchronized(pending) { pending.clear() }
    }

    private fun close(session: Session) {
        if (sessions.remove(session.id, session)) {
            lastServed[session.peerReplica] = run.clock()
            run.peers.sessionClosed(session.peerReplica)
        }
    }

    private fun randomField(bytes: Int): String = SyncBase64.encode(ByteArray(bytes).also(run.random::nextBytes))

    private fun refuse(
        status: Int,
        code: String,
    ) = SyncReply(status, SyncProtocol.error(code))
}
