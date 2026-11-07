package com.kelpie.browser.account

import kotlinx.coroutines.flow.StateFlow

data class KelpieUOAIdentity(val subject: String?, val session: String?)

/** The containing app owns sign-in, refresh, revocation and credential storage. */
interface KelpieUOASession {
    /** Changes on sign-out and account/session replacement; null means signed out. */
    val identity: StateFlow<KelpieUOAIdentity>

    suspend fun request(path: String, method: String, body: String?, version: String?): UOATransport.Response

    suspend fun settingsRequest(): okhttp3.Request

    fun signIn()

    fun signOut()
}
