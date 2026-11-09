package com.kelpie.browser.sync

import com.kelpie.browser.account.UOAAccount
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject

/**
 * Bridges sync to [UOAAccount]. Requests go through `UOAAccount.request`, so the
 * access token never leaves the account module. The sync service bounds how many
 * calls run at once. Fences run on the account's main dispatcher, as [com.kelpie.browser.account.UOALocalPairing] does.
 */
class UOASyncAccount(
    scope: CoroutineScope,
) : SyncAccount {
    override val identity: StateFlow<SyncIdentity?> =
        UOAAccount.state
            .map { state -> state.profile?.let { profile -> UOAAccount.pairingSession?.let { SyncIdentity(profile.subject, it) } } }
            .distinctUntilChanged()
            .stateIn(scope, SharingStarted.Eagerly, null)

    override suspend fun issueTicket(
        identity: SyncIdentity,
        challenge: String,
        clientId: String,
    ): String {
        val body =
            buildJsonObject {
                put("challenge", JsonPrimitive(challenge))
                put("clientId", JsonPrimitive(clientId))
            }
        val response = fenced(identity) { UOAAccount.request("/oauth/kelpie/pair", "POST", body.toString()).json() }
        return response.string("pairing_ticket")?.takeIf { it.isNotEmpty() && it.length <= MAX_TICKET }
            ?: throw SyncFailure("UOA_UNAVAILABLE", "UOA returned no pairing ticket")
    }

    override suspend fun validateTicket(
        identity: SyncIdentity,
        ticket: String,
        challenge: String,
        clientId: String,
    ): Boolean {
        val body =
            buildJsonObject {
                put("ticket", JsonPrimitive(ticket))
                put("challenge", JsonPrimitive(challenge))
                put("clientId", JsonPrimitive(clientId))
            }
        val decision = fenced(identity) { UOAAccount.request("/oauth/kelpie/pair/validate", "POST", body.toString()).json() }
        return decision.bool("active") == true
    }

    private suspend fun <T> fenced(
        identity: SyncIdentity,
        call: suspend () -> T,
    ): T =
        withContext(Dispatchers.Main.immediate) {
            if (current() != identity) throw SyncFailure("STALE", "account changed")
            val result =
                try {
                    call()
                } catch (error: kotlinx.coroutines.CancellationException) {
                    if (current() != identity) throw SyncFailure("STALE", "account changed")
                    throw error
                } catch (error: Exception) {
                    throw SyncFailure("UOA_UNAVAILABLE", "UOA request failed")
                }
            if (current() != identity) throw SyncFailure("STALE", "account changed")
            result
        }

    private fun current(): SyncIdentity? =
        UOAAccount.state.value.profile
            ?.let { profile -> UOAAccount.pairingSession?.let { SyncIdentity(profile.subject, it) } }

    private companion object {
        const val MAX_TICKET = 8192
    }
}
