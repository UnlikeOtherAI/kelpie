package com.kelpie.browser.sync

import kotlinx.coroutines.flow.StateFlow

/** The signed-in UOA account as sync sees it. A new sign-in is a new [generation]. */
data class SyncIdentity(
    val subject: String,
    val generation: String,
)

/**
 * UOA proofs for the handshake. Implementations use the app's existing UOA
 * session and never hand a spendable credential to sync. Every call is fenced
 * by [identity]: it fails when the account is no longer that identity.
 */
interface SyncAccount {
    val identity: StateFlow<SyncIdentity?>

    /** `POST /oauth/kelpie/pair {challenge, clientId}` → the pairing ticket. */
    suspend fun issueTicket(
        identity: SyncIdentity,
        challenge: String,
        clientId: String,
    ): String

    /** `POST /oauth/kelpie/pair/validate`; true only for `{active:true}` from a live account. */
    suspend fun validateTicket(
        identity: SyncIdentity,
        ticket: String,
        challenge: String,
        clientId: String,
    ): Boolean
}
