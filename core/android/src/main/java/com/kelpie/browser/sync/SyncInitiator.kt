package com.kelpie.browser.sync

import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch
import kotlinx.coroutines.withTimeoutOrNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import java.util.concurrent.atomic.AtomicLong
import java.util.concurrent.atomic.AtomicReference
import kotlin.math.abs

/** One HTTP POST to a peer's sync listener. */
interface SyncTransport {
    data class Response(
        val status: Int,
        val body: String,
    )

    suspend fun post(
        target: PeerTarget,
        path: String,
        body: String,
        session: String?,
        timeoutMs: Long,
    ): Response
}

/**
 * The requesting side: the handshake, then one long-poll pull and pushes on
 * local changes until the session ends. Only the initiator sends requests.
 */
class SyncInitiator(
    private val run: SyncRun,
    private val transport: SyncTransport,
) {
    class Session internal constructor(
        val id: String,
        val peerReplica: String,
        val target: PeerTarget,
        internal val keys: SyncSessionKeys,
        val expiresAt: Long,
    ) {
        internal val seq = AtomicLong(0)
    }

    suspend fun handshake(
        peerReplica: String,
        target: PeerTarget,
    ): Session {
        val own = SyncCrypto.generateKeyPair(run.random)
        val nonce = SyncBase64.encode(ByteArray(32).also(run.random::nextBytes))
        val hello =
            buildJsonObject {
                put("v", SyncProtocol.VERSION)
                put("replica", run.replica)
                put("hint", run.hints().first)
                put("now", run.clock())
                put("platform", SyncProtocol.PLATFORM)
                put("name", run.deviceName)
                put("key", own.encodedPublicKey)
                put("nonce", nonce)
            }
        val reply = call(target, "/v1/sync/hello", hello, null, HANDSHAKE_TIMEOUT_MS)
        if (SyncCore.invalid("hello-reply", reply) != null) throw SyncFailure("PROTOCOL", "invalid hello reply")
        if (reply.string("replica") != peerReplica) throw SyncFailure("PROTOCOL", "peer replica changed")
        run.peers.introduced(peerReplica, reply.string("platform"), reply.string("name"))
        if (abs(reply.long("now")!! - run.clock()) > SyncProtocol.MAX_CLOCK_SKEW_MS) throw SyncFailure("CLOCK_SKEW")
        val peerKey = SyncCrypto.decodePublicKey(reply.string("key")!!) ?: throw SyncFailure("PROTOCOL", "invalid peer key")
        val challenge =
            SyncCore.challenge(
                HelloSide(run.replica, own.encodedPublicKey, nonce),
                HelloSide(peerReplica, reply.string("key")!!, reply.string("nonce")!!),
            )
        val ticket = run.issueTicket(challenge, SyncProtocol.initiatorClientId(run.replica))
        val handshakeId = reply.string("handshakeId")!!
        val auth =
            call(
                target,
                "/v1/sync/auth",
                buildJsonObject {
                    put("handshakeId", handshakeId)
                    put("ticket", ticket)
                },
                null,
                HANDSHAKE_TIMEOUT_MS,
            )
        if (SyncCore.invalid("auth-reply", auth) != null) throw SyncFailure("PROTOCOL", "invalid auth reply")
        val proven = run.validateTicket(auth.string("ticket")!!, challenge, SyncProtocol.responderClientId(peerReplica))
        if (!proven) throw SyncFailure("AUTH_FAILED")
        run.requireCurrent()
        val keys = SyncChannel.deriveKeys(own.privateKey, peerKey, challenge)
        val expiresAt = minOf(auth.long("sessionExpiresAt")!!, run.clock() + SyncProtocol.SESSION_MS)
        return Session(handshakeId, peerReplica, target, keys, expiresAt)
    }

    /**
     * Runs pulls and pushes until the session expires (normal return) or fails
     * (throws). The first pull returns at once; later pulls are long polls.
     */
    suspend fun serve(session: Session) {
        val theirWatermark = AtomicReference<JsonObject?>(null)
        val firstPage = CompletableDeferred<Unit>()
        coroutineScope {
            val pulls = launch { pullLoop(session, theirWatermark, firstPage) }
            val pushes =
                launch {
                    firstPage.await()
                    pushLoop(session, theirWatermark)
                }
            pulls.join()
            pushes.cancel()
        }
    }

    private suspend fun pullLoop(
        session: Session,
        theirWatermark: AtomicReference<JsonObject?>,
        firstPage: CompletableDeferred<Unit>,
    ) {
        var caughtUp = false
        while (run.clock() < session.expiresAt) {
            val pull =
                buildJsonObject {
                    put("op", "pull")
                    put("replica", run.replica)
                    put("since", run.watermark(session.peerReplica))
                    put("wait", if (caughtUp) SyncProtocol.MAX_WAIT_MS else 0)
                }
            val response = exchange(session, pull)
            if (response.string("replica") != session.peerReplica) throw SyncFailure("PROTOCOL", "pull from another replica")
            response.obj("yourWatermark")?.let { theirWatermark.set(it) }
            if (response.bool("warming") == true) {
                firstPage.complete(Unit)
                caughtUp = false
                delay(WARMING_RETRY_MS)
                continue
            }
            run.commitPull(response)
            firstPage.complete(Unit)
            val more = response.bool("more") == true
            if (!more) {
                run.completedFrom(session.peerReplica)
                run.peers.synced(session.peerReplica)
            }
            caughtUp = !more
        }
    }

    private suspend fun pushLoop(
        session: Session,
        theirWatermark: AtomicReference<JsonObject?>,
    ) {
        while (true) {
            val version = run.feed.value
            pushPending(session, theirWatermark)
            val remaining = session.expiresAt - run.clock()
            if (remaining <= 0) return
            withTimeoutOrNull(remaining) { run.feed.first { it != version } } ?: return
        }
    }

    private suspend fun pushPending(
        session: Session,
        theirWatermark: AtomicReference<JsonObject?>,
    ) {
        while (true) {
            val known = theirWatermark.get() ?: return
            val push = run.buildPush(known) ?: return
            val reply = exchange(session, push)
            val next = reply.obj("yourWatermark") ?: throw SyncFailure("PROTOCOL", "push reply has no watermark")
            // A responder whose watermark does not move would make this loop spin.
            if (next.string("replica") == known.string("replica") && (next.long("seq") ?: 0) <= (known.long("seq") ?: 0)) return
            theirWatermark.set(next)
            if (push.bool("more") != true) return
        }
    }

    /** Seals [plaintext] as the next request and opens the response sealed under the same seq. */
    private suspend fun exchange(
        session: Session,
        plaintext: JsonObject,
    ): JsonObject {
        run.requireCurrent()
        val seq = session.seq.incrementAndGet()
        val box = SyncChannel.seal(session.keys.i2r, session.id, SyncChannel.REQUEST, seq, plaintext.toString())
        val envelope =
            buildJsonObject {
                put("seq", seq)
                put("box", box)
            }
        val wait = plaintext.long("wait") ?: 0
        val reply = call(session.target, "/v1/sync/exchange", envelope, session.id, wait + EXCHANGE_TIMEOUT_MS)
        if (SyncCore.invalid("exchange", reply) != null || reply.long("seq") != seq) throw SyncFailure("PROTOCOL", "invalid exchange reply")
        val opened =
            SyncChannel.open(session.keys.r2i, session.id, SyncChannel.RESPONSE, seq, reply.string("box")!!)
                ?: throw SyncFailure("PROTOCOL", "response did not authenticate")
        run.requireCurrent()
        return SyncJson.parseObject(opened) ?: throw SyncFailure("PROTOCOL", "response is not JSON")
    }

    private suspend fun call(
        target: PeerTarget,
        path: String,
        body: JsonObject,
        session: String?,
        timeoutMs: Long,
    ): JsonObject {
        run.requireCurrent()
        val response =
            try {
                transport.post(target, path, body.toString(), session, timeoutMs)
            } catch (error: java.io.IOException) {
                throw SyncFailure("UNREACHABLE", "peer unreachable")
            }
        run.requireCurrent()
        val parsed = SyncJson.parseObject(response.body)
        if (response.status != 200) {
            val code = parsed?.string("error")?.takeIf { it.length <= 40 } ?: "HTTP_${response.status}"
            throw SyncFailure(if (response.status == 401) "SYNC_SESSION" else code)
        }
        return parsed ?: throw SyncFailure("PROTOCOL", "reply is not JSON")
    }

    private companion object {
        const val HANDSHAKE_TIMEOUT_MS = 30_000L
        const val EXCHANGE_TIMEOUT_MS = 30_000L
        const val WARMING_RETRY_MS = 2_000L
    }
}
