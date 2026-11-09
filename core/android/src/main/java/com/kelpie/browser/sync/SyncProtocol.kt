package com.kelpie.browser.sync

import com.kelpie.browser.nativecore.CookieSyncNative
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put

/** Limits and wire constants from docs/plans/2026-11-09-p2p-cookie-sync.md. */
object SyncProtocol {
    const val VERSION = 1
    const val SERVICE_TYPE = "_kelpie-sync._tcp"
    const val PLATFORM = "android"
    const val SESSION_HEADER = "X-Kelpie-Sync-Session"

    const val MAX_CLOCK_SKEW_MS = 2 * 60_000L
    const val PENDING_TTL_MS = 60_000L
    const val MAX_PENDING = 8
    const val SESSION_MS = 10 * 60_000L
    const val SMALL_BODY_BYTES = 16 * 1024L
    const val EXCHANGE_BODY_BYTES = 4L * 1024 * 1024
    const val SMALL_READ_DEADLINE_MS = 5_000L
    const val EXCHANGE_READ_DEADLINE_MS = 30_000L
    const val MAX_WAIT_MS = 25_000L
    const val HELLO_PER_SOURCE_PER_MIN = 10
    const val HELLO_TOTAL_PER_MIN = 60
    const val OUTGOING_HANDSHAKES_PER_MIN = 10
    const val BACKOFF_MIN_MS = 5_000L
    const val BACKOFF_MAX_MS = 5 * 60_000L
    const val FALLBACK_INITIATE_MS = 15_000L
    const val MAX_UOA_CALLS = 2
    const val WARMUP_PEER_WINDOW_MS = 15_000L
    const val WARMUP_MAX_MS = 30_000L

    fun initiatorClientId(replica: String) = "kelpie-sync:i:$replica"

    fun responderClientId(replica: String) = "kelpie-sync:r:$replica"

    fun error(code: String): JsonObject = buildJsonObject { put("error", code) }

    /** Overflow-safe skew gate: a peer can send any Long in `now`. */
    fun withinSkew(
        peerNow: Long,
        localNow: Long,
    ): Boolean =
        try {
            kotlin.math.abs(Math.subtractExact(peerNow, localNow)) <= MAX_CLOCK_SKEW_MS
        } catch (_: ArithmeticException) {
            false
        }

    /** The documented codes a peer may send back; anything else becomes PEER_ERROR. */
    private val peerCodes =
        setOf(
            "ACCOUNT_MISMATCH",
            "AUTH_FAILED",
            "BAD_REQUEST",
            "CLOCK_SKEW",
            "DUPLICATE_CONTENT_LENGTH",
            "FORBIDDEN",
            "HEADERS_TOO_LARGE",
            "INVALID_BOX",
            "INVALID_CONTENT_LENGTH",
            "INVALID_MESSAGE",
            "LENGTH_REQUIRED",
            "METHOD_NOT_ALLOWED",
            "NOT_FOUND",
            "ORIGIN_REJECTED",
            "PAYLOAD_TOO_LARGE",
            "PROOF_REJECTED",
            "RATE_LIMITED",
            "REPLAY",
            "REPLAYED",
            "REQUEST_TIMEOUT",
            "SESSION_EXISTS",
            "SYNC_SESSION",
            "TIMEOUT",
            "TRANSFER_ENCODING",
            "UNAVAILABLE",
            "UNSUPPORTED_MEDIA_TYPE",
            "UOA_BUSY",
            "UOA_UNAVAILABLE",
        )

    fun peerCode(
        raw: String?,
        status: Int,
    ): String =
        when (raw) {
            null -> "HTTP_$status"
            in peerCodes -> raw
            else -> "PEER_ERROR"
        }
}

/** core-sync's stateless helpers. */
object SyncCore {
    /** Returns null when [message] has the shape of [kind], otherwise a short reason. */
    fun invalid(
        kind: String,
        message: JsonObject,
    ): String? {
        val result = SyncJson.native(CookieSyncNative.validate(kind, message.toString()))
        return if (result.bool("ok") == true) null else result.string("error") ?: "invalid"
    }

    fun challenge(
        initiator: HelloSide,
        responder: HelloSide,
    ): String {
        val pair =
            buildJsonObject {
                put("initiator", initiator.json())
                put("responder", responder.json())
            }
        return SyncJson.native(CookieSyncNative.transcript(pair.toString())).string("challenge")
            ?: throw SyncFailure("INTERNAL", "no challenge")
    }

    /** The current hint and the accepted set (yesterday, today, tomorrow, UTC). */
    fun hints(
        subject: String,
        now: Long,
    ): Pair<String, Set<String>> {
        val result = SyncJson.native(CookieSyncNative.accountHints(subject, now))
        val current = result.string("current") ?: throw SyncFailure("INTERNAL", "no hint")
        val accepted =
            result
                .array("accepted")
                .orEmpty()
                .mapNotNull { (it as? JsonPrimitive)?.content }
                .toSet()
        return current to accepted
    }
}

/** The three transcript values one side contributes, exactly as sent. */
data class HelloSide(
    val replica: String,
    val key: String,
    val nonce: String,
) {
    fun json(): JsonObject =
        buildJsonObject {
            put("replica", replica)
            put("key", key)
            put("nonce", nonce)
        }
}
