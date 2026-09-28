package com.kelpie.browser.account

import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put

/**
 * Access and refresh token lifecycle. Rotated refresh tokens are persisted before the new access
 * token is used, concurrent callers share one refresh, and work from an older generation never
 * touches storage. Only the client id and refresh token are ever persisted.
 */
class UOACredentials(
    private val storage: UOASessionStorage,
    private val transport: suspend (String, String, String?, String?, String?) -> UOATransport.Response,
    private val clock: () -> Long = System::currentTimeMillis,
) {
    enum class Resume { RESTORED, REJECTED, UNAVAILABLE }

    private val lock = Mutex()

    @Volatile var generation = 0L
        private set
    private var session: UOAStoredSession? = null
    private var accessToken: String? = null
    var expiresAt = 0L
        private set

    /** Survives restarts. Memory-only sessions (no refresh token issued) end at access-token expiry. */
    val persistent: Boolean get() = session != null
    val active: Boolean get() = accessToken != null || session != null

    fun hasStoredSession() = storage.load() != null

    /** Rotates the stored session. A failure in transit keeps it stored for the next attempt. */
    suspend fun resume(): Resume {
        val expected = generation
        session = storage.load() ?: return Resume.REJECTED
        return try {
            refresh(null, expected)
            Resume.RESTORED
        } catch (_: UOASessionRejected) {
            Resume.REJECTED
        } catch (cancelled: CancellationException) {
            throw cancelled
        } catch (_: Exception) {
            if (expected == generation) session = null
            Resume.UNAVAILABLE
        }
    }

    /** Stores what a token response issued; the refresh token is persisted before the access token is used. */
    fun accept(
        grant: UOATokenGrant,
        clientId: String,
    ) {
        val next = grant.refreshToken?.let { UOAStoredSession(clientId, it) }
        if (next != null) storage.save(next) else storage.clear()
        session = next
        accessToken = grant.accessToken
        expiresAt = clock() + grant.expiresIn * 1000
    }

    suspend fun validToken(expected: Long): String {
        val token = accessToken
        if (token != null && expiresAt - clock() > REFRESH_MARGIN_MS) return token
        if (session != null) return refresh(token, expected)
        if (token != null && expiresAt > clock()) return token
        throw UOATransport.Failure(401)
    }

    /** Single-flight rotation. A token a concurrent caller already replaced is reused. */
    suspend fun refresh(
        stale: String?,
        expected: Long,
    ): String =
        lock.withLock {
            if (expected != generation) throw CancellationException()
            accessToken?.takeIf { it != stale && expiresAt - clock() > REFRESH_MARGIN_MS }?.let { return@withLock it }
            val stored = session ?: throw UOASessionRejected()
            val body =
                buildJsonObject {
                    put("grant_type", "refresh_token")
                    put("refresh_token", stored.refreshToken)
                    put("client_id", stored.clientId)
                }
            val grant =
                try {
                    UOATokenGrant.parse(transport("/oauth/token", "POST", null, body.toString(), null))
                } catch (failure: UOATransport.Failure) {
                    if (!failure.rejectsCredential) throw failure
                    if (expected == generation) forget()
                    throw UOASessionRejected()
                }
            if (expected != generation) throw CancellationException()
            accept(grant, stored.clientId)
            grant.accessToken
        }

    /** Starts a new generation and returns the session it dropped, so a user sign-out can revoke it. */
    fun reset(clearStorage: Boolean): UOAStoredSession? {
        generation++
        val dropped = session ?: storage.load()
        if (clearStorage) storage.clear()
        session = null
        accessToken = null
        expiresAt = 0
        return dropped
    }

    /** Best effort: the local session is already gone, so every revocation failure is ignored. */
    suspend fun revoke(dropped: UOAStoredSession) {
        val body =
            buildJsonObject {
                put("token", dropped.refreshToken)
                put("client_id", dropped.clientId)
            }
        runCatching { transport("/oauth/revoke", "POST", null, body.toString(), null) }
    }

    private fun forget() {
        storage.clear()
        session = null
    }

    private companion object {
        const val REFRESH_MARGIN_MS = 60_000L
    }
}
