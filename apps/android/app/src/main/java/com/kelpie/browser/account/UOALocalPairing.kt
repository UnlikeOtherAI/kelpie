package com.kelpie.browser.account

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.longOrNull

/** UOA owns the account comparison. Keep all session fences on the account's main dispatcher. */
object UOALocalPairing {
    suspend fun session(): String? = withContext(Dispatchers.Main.immediate) { UOAAccount.pairingSession }

    suspend fun verify(
        ticket: String,
        challenge: String,
        clientId: String,
        session: String,
    ): Long? =
        withContext(Dispatchers.Main.immediate) {
            if (UOAAccount.pairingSession != session) return@withContext null
            val decision =
                runCatching {
                    val body =
                        buildJsonObject {
                            put("ticket", JsonPrimitive(ticket))
                            put("challenge", JsonPrimitive(challenge))
                            put("clientId", JsonPrimitive(clientId))
                        }
                    UOAAccount.request("/oauth/kelpie/pair/validate", "POST", body.toString()).json()
                }.getOrNull() ?: return@withContext null
            if (decision["active"]?.jsonPrimitive?.booleanOrNull != true || UOAAccount.pairingSession != session) {
                return@withContext null
            }
            decision["expires_at"]?.jsonPrimitive?.longOrNull
        }
}
