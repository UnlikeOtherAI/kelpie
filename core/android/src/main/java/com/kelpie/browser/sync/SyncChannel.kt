package com.kelpie.browser.sync

import java.nio.ByteBuffer
import java.security.interfaces.ECPrivateKey
import java.security.interfaces.ECPublicKey

/** Direction keys of one session: requests are sealed with [i2r], responses with [r2i]. */
class SyncSessionKeys(
    val i2r: ByteArray,
    val r2i: ByteArray,
)

/** Key derivation and AES-GCM framing for `/v1/sync/exchange`, fixed by `handshake-v1.json`. */
object SyncChannel {
    const val REQUEST = "req"
    const val RESPONSE = "res"
    private const val LABEL = "kelpie-sync-v1"

    fun deriveKeys(
        own: ECPrivateKey,
        peer: ECPublicKey,
        challenge: String,
    ): SyncSessionKeys {
        val transcript = requireNotNull(SyncBase64.decode(challenge)) { "challenge is not base64url" }
        val shared = SyncCrypto.sharedSecret(own, peer)
        try {
            return SyncSessionKeys(
                i2r = SyncCrypto.hkdf(shared, transcript, "$LABEL i2r".toByteArray(Charsets.UTF_8), 32),
                r2i = SyncCrypto.hkdf(shared, transcript, "$LABEL r2i".toByteArray(Charsets.UTF_8), 32),
            )
        } finally {
            shared.fill(0)
        }
    }

    /** 4 zero bytes || 64-bit big-endian request seq. */
    fun nonce(seq: Long): ByteArray =
        ByteBuffer
            .allocate(12)
            .putInt(0)
            .putLong(seq)
            .array()

    fun aad(
        sessionId: String,
        direction: String,
        seq: Long,
    ): ByteArray = "$LABEL\u0000$sessionId\u0000$direction\u0000$seq".toByteArray(Charsets.UTF_8)

    fun seal(
        key: ByteArray,
        sessionId: String,
        direction: String,
        seq: Long,
        plaintext: String,
    ): String = SyncBase64.encode(SyncCrypto.seal(key, nonce(seq), aad(sessionId, direction, seq), plaintext.toByteArray(Charsets.UTF_8)))

    /** Returns null for a box that is malformed or does not authenticate. */
    fun open(
        key: ByteArray,
        sessionId: String,
        direction: String,
        seq: Long,
        box: String,
    ): String? {
        val bytes = SyncBase64.decode(box) ?: return null
        if (bytes.size < 16) return null
        return SyncCrypto.open(key, nonce(seq), aad(sessionId, direction, seq), bytes)?.toString(Charsets.UTF_8)
    }
}

/**
 * The responder's 64-entry replay window: accepts a seq it has not seen that is
 * less than 64 below the highest seen. Called only after the box authenticated.
 */
class ReplayWindow {
    private var highest = 0L
    private var seen = 0L // bit i set: (highest - i) was accepted

    @Synchronized fun accept(seq: Long): Boolean {
        if (seq <= 0) return false
        if (seq > highest) {
            val shift = seq - highest
            seen = if (shift >= WINDOW) 0L else seen shl shift.toInt()
            seen = seen or 1L
            highest = seq
            return true
        }
        val offset = highest - seq
        if (offset >= WINDOW) return false
        val bit = 1L shl offset.toInt()
        if (seen and bit != 0L) return false
        seen = seen or bit
        return true
    }

    private companion object {
        const val WINDOW = 64L
    }
}
