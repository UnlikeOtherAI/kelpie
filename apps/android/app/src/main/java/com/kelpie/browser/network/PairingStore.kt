package com.kelpie.browser.network

import android.content.Context
import android.util.Base64
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import java.io.File
import java.security.MessageDigest
import java.security.SecureRandom
import java.util.UUID
import kotlin.experimental.xor

/**
 * State + storage for the pairing/auth system on Android.
 *
 * Persistent state (token hashes only) is written atomically to
 * `filesDir/pairings.json` — Android's app-private storage is already
 * sandboxed per-UID, so the file is unreachable to other apps without root.
 * Hash-only storage means filesystem-level theft does not yield bearer tokens.
 *
 * In-memory state (pending requests, session tokens, denied addresses)
 * lives only for the lifetime of the process.
 */
class PairingStore(
    private val file: File,
) {
    @Serializable
    data class PairingRecord(
        val clientId: String,
        val clientName: String,
        val tokenHashSha256: String,
        val approvedAt: Long,
        var lastSeenAt: Long,
    )

    @Serializable
    private data class StoredEnvelope(
        val version: Int = 1,
        val pairings: List<PairingRecord> = emptyList(),
    )

    data class PendingRequest(
        val requestId: String,
        val clientId: String,
        val clientName: String,
        val sourceAddress: String,
        val createdAt: Long,
        val expiresAt: Long,
    )

    data class SessionApproval(
        val clientId: String,
        val clientName: String,
        val tokenHashSha256: String,
        val approvedAt: Long,
    )

    data class PendingIssuance(
        val token: String,
        val scope: String,
        val sourceAddress: String,
        val createdAt: Long,
        val expiresAt: Long,
    )

    enum class PairStartResult { CREATED, DENIED }

    data class PairStart(
        val result: PairStartResult,
        val request: PendingRequest? = null,
    )

    companion object {
        const val PENDING_TTL_MS: Long = 5 * 60 * 1000
        const val DENY_TTL_MS: Long = 10 * 60 * 1000
        const val CLIENT_NAME_MAX_LENGTH: Int = 64

        fun forContext(context: Context): PairingStore = PairingStore(File(context.filesDir, "pairings.json"))

        fun sanitizeClientName(raw: String): String {
            val stripped = raw.filter { !it.isISOControl() }
            return stripped.take(CLIENT_NAME_MAX_LENGTH).trim()
        }

        fun hashToken(plaintext: String): String {
            val digest = MessageDigest.getInstance("SHA-256").digest(plaintext.toByteArray(Charsets.UTF_8))
            return digest.joinToString("") { "%02x".format(it) }
        }

        fun constantTimeEqualsHex(
            lhs: String,
            rhs: String,
        ): Boolean {
            if (lhs.length != rhs.length) return false
            val a = lhs.toByteArray(Charsets.US_ASCII)
            val b = rhs.toByteArray(Charsets.US_ASCII)
            var diff: Byte = 0
            for (i in a.indices) diff = diff xor (a[i] xor b[i])
            return diff == 0.toByte()
        }

        fun generateToken(): String {
            val bytes = ByteArray(32)
            SecureRandom().nextBytes(bytes)
            return base64UrlEncode(bytes)
        }

        fun generateRequestId(): String = generateToken()

        fun newClientId(): String = UUID.randomUUID().toString()

        private fun base64UrlEncode(bytes: ByteArray): String = Base64.encodeToString(bytes, Base64.NO_PADDING or Base64.NO_WRAP or Base64.URL_SAFE)
    }

    private val lock = Any()
    private var persistent: MutableList<PairingRecord> = mutableListOf()
    private val sessions: MutableList<SessionApproval> = mutableListOf()
    private val pending: MutableMap<String, PendingRequest> = mutableMapOf()
    private val deniedSources: MutableMap<String, Long> = mutableMapOf()
    private val pendingBySource: MutableMap<String, String> = mutableMapOf()
    private val pendingIssuances: MutableMap<String, PendingIssuance> = mutableMapOf()

    private val json =
        Json {
            ignoreUnknownKeys = true
            encodeDefaults = true
        }

    init {
        load()
    }

    private fun load() {
        synchronized(lock) {
            if (!file.exists()) return
            runCatching {
                val text = file.readText()
                val envelope = json.decodeFromString(StoredEnvelope.serializer(), text)
                persistent = envelope.pairings.toMutableList()
            }
        }
    }

    private fun persistLocked() {
        val envelope = StoredEnvelope(1, persistent.toList())
        val data = json.encodeToString(StoredEnvelope.serializer(), envelope)
        val tmp = File(file.parentFile, "${file.name}.tmp")
        try {
            tmp.writeText(data)
            // Best-effort restrictive perms; on Android app-private files are
            // already inaccessible to other apps regardless.
            tmp.setReadable(false, false)
            tmp.setReadable(true, true)
            tmp.setWritable(false, false)
            tmp.setWritable(true, true)
            if (!tmp.renameTo(file)) {
                // renameTo can fail on some filesystems if target exists; delete + retry.
                file.delete()
                tmp.renameTo(file)
            }
        } catch (t: Throwable) {
            android.util.Log.w("PairingStore", "persist failed: ${t.message}")
        }
    }

    fun startPairing(
        clientId: String,
        clientName: String,
        sourceAddress: String,
    ): PairStart {
        synchronized(lock) {
            gcLocked(System.currentTimeMillis())
            val now = System.currentTimeMillis()
            val expiresAt = deniedSources[sourceAddress] ?: 0
            if (expiresAt > now) return PairStart(PairStartResult.DENIED)

            pendingBySource[sourceAddress]?.let { existing -> pending.remove(existing) }

            val req =
                PendingRequest(
                    requestId = generateRequestId(),
                    clientId = clientId,
                    clientName = sanitizeClientName(clientName),
                    sourceAddress = sourceAddress,
                    createdAt = now,
                    expiresAt = now + PENDING_TTL_MS,
                )
            pending[req.requestId] = req
            pendingBySource[sourceAddress] = req.requestId
            return PairStart(PairStartResult.CREATED, req)
        }
    }

    fun visiblePending(): List<PendingRequest> =
        synchronized(lock) {
            gcLocked(System.currentTimeMillis())
            pending.values.sortedBy { it.createdAt }
        }

    fun pendingRequest(requestId: String): PendingRequest? =
        synchronized(lock) {
            gcLocked(System.currentTimeMillis())
            pending[requestId]
        }

    fun approve(
        requestId: String,
        persist: Boolean,
    ): Pair<String, String>? {
        synchronized(lock) {
            gcLocked(System.currentTimeMillis())
            val entry = pending.remove(requestId) ?: return null
            pendingBySource.remove(entry.sourceAddress)

            val token = generateToken()
            val hash = hashToken(token)
            val now = System.currentTimeMillis()
            val scope: String
            if (persist) {
                persistent.removeAll { it.clientId == entry.clientId }
                persistent.add(
                    PairingRecord(
                        clientId = entry.clientId,
                        clientName = entry.clientName,
                        tokenHashSha256 = hash,
                        approvedAt = now,
                        lastSeenAt = now,
                    ),
                )
                persistLocked()
                scope = "persistent"
            } else {
                sessions.removeAll { it.clientId == entry.clientId }
                sessions.add(
                    SessionApproval(
                        clientId = entry.clientId,
                        clientName = entry.clientName,
                        tokenHashSha256 = hash,
                        approvedAt = now,
                    ),
                )
                scope = "session"
            }
            pendingIssuances[requestId] =
                PendingIssuance(
                    token = token,
                    scope = scope,
                    sourceAddress = entry.sourceAddress,
                    createdAt = now,
                    expiresAt = now + PENDING_TTL_MS,
                )
            return token to scope
        }
    }

    fun takeIssuance(
        requestId: String,
        sourceAddress: String,
    ): PendingIssuance? {
        synchronized(lock) {
            gcLocked(System.currentTimeMillis())
            val issuance = pendingIssuances[requestId] ?: return null
            if (issuance.sourceAddress != sourceAddress) return null
            pendingIssuances.remove(requestId)
            return issuance
        }
    }

    fun wasRecentlyDenied(sourceAddress: String): Boolean =
        synchronized(lock) {
            gcLocked(System.currentTimeMillis())
            val expiresAt = deniedSources[sourceAddress] ?: 0
            expiresAt > System.currentTimeMillis()
        }

    fun deny(requestId: String) {
        synchronized(lock) {
            val entry = pending.remove(requestId) ?: return
            pendingBySource.remove(entry.sourceAddress)
            deniedSources[entry.sourceAddress] = System.currentTimeMillis() + DENY_TTL_MS
        }
    }

    fun validateBearer(token: String): String? {
        val hash = hashToken(token)
        synchronized(lock) {
            val match = persistent.firstOrNull { constantTimeEqualsHex(it.tokenHashSha256, hash) }
            if (match != null) {
                match.lastSeenAt = System.currentTimeMillis()
                return match.clientId
            }
            val session = sessions.firstOrNull { constantTimeEqualsHex(it.tokenHashSha256, hash) }
            return session?.clientId
        }
    }

    fun revoke(clientId: String): Boolean {
        synchronized(lock) {
            val sizeBefore = persistent.size + sessions.size
            persistent.removeAll { it.clientId == clientId }
            sessions.removeAll { it.clientId == clientId }
            val changed = sizeBefore != persistent.size + sessions.size
            if (changed) persistLocked()
            return changed
        }
    }

    fun listPersistent(): List<PairingRecord> = synchronized(lock) { persistent.toList() }

    fun listSessions(): List<SessionApproval> = synchronized(lock) { sessions.toList() }

    fun listDeniedSources(): List<Pair<String, Long>> =
        synchronized(lock) {
            gcLocked(System.currentTimeMillis())
            deniedSources.map { it.key to it.value }
        }

    private fun gcLocked(now: Long) {
        val expired = pending.values.filter { it.expiresAt <= now }.map { it.requestId }
        for (id in expired) {
            val entry = pending.remove(id) ?: continue
            if (pendingBySource[entry.sourceAddress] == id) pendingBySource.remove(entry.sourceAddress)
        }
        deniedSources.entries.removeAll { it.value <= now }
        pendingIssuances.entries.removeAll { it.value.expiresAt <= now }
    }
}
