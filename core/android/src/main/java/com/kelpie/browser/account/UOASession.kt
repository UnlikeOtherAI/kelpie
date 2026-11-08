package com.kelpie.browser.account

import com.kelpie.browser.storage.SecretStore
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.long
import kotlinx.serialization.json.put

/** The only UOA material kept across launches: the public client id and its rotating refresh token. */
data class UOAStoredSession(
    val clientId: String,
    val refreshToken: String,
) {
    fun encode(): String =
        buildJsonObject {
            put("client_id", clientId)
            put("refresh_token", refreshToken)
        }.toString()

    companion object {
        fun decode(raw: String?): UOAStoredSession? =
            runCatching {
                val json = Json.parseToJsonElement(raw!!).jsonObject
                UOAStoredSession(json["client_id"]!!.jsonPrimitive.content, json["refresh_token"]!!.jsonPrimitive.content)
            }.getOrNull()?.takeIf { it.clientId.isNotEmpty() && it.refreshToken.isNotEmpty() }
    }
}

interface UOASessionStorage {
    fun load(): UOAStoredSession?

    fun save(session: UOAStoredSession)

    fun clear()
}

/** Encrypted storage through [SecretStore] (Android Keystore-backed EncryptedSharedPreferences). */
class UOASecretSessionStorage(
    private val secrets: SecretStore,
) : UOASessionStorage {
    override fun load() = UOAStoredSession.decode(secrets.get(KEY))

    override fun save(session: UOAStoredSession) = secrets.set(KEY, session.encode())

    override fun clear() = secrets.remove(KEY)

    companion object {
        const val KEY = "uoa.session.v1"
    }
}

/** A successful `/oauth/token` response from either the code or the refresh grant. */
data class UOATokenGrant(
    val accessToken: String,
    val expiresIn: Long,
    /** Absent from UOA servers that do not issue refresh tokens; the session is then memory-only. */
    val refreshToken: String?,
) {
    companion object {
        fun parse(response: UOATransport.Response): UOATokenGrant =
            try {
                val json = response.json()
                UOATokenGrant(
                    json["access_token"]!!.jsonPrimitive.content.also { require(it.isNotEmpty()) },
                    json["expires_in"]!!
                        .jsonPrimitive.long
                        .coerceAtMost(86400)
                        .also { require(it > 0) },
                    json["refresh_token"]?.jsonPrimitive?.contentOrNull?.takeIf { it.isNotEmpty() },
                )
            } catch (_: Exception) {
                throw UOATransport.Failure(0)
            }
    }
}

/** UOA refused the credential itself, as opposed to the request failing in transit. */
val UOATransport.Failure.rejectsCredential: Boolean get() = status == 400 || status == 401 || status == 403

/** UOA refused the stored refresh token, which has already been forgotten. */
class UOASessionRejected : Exception()
