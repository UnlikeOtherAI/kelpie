package com.kelpie.browser.account

import android.content.Context
import android.content.Intent
import android.net.Uri
import com.kelpie.browser.MainActivity
import com.kelpie.browser.browser.BookmarkStore
import com.kelpie.browser.storage.SecretStore
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.put
import java.lang.ref.WeakReference
import java.util.UUID

/**
 * Application-scoped coordinator. Profile, avatar, access tokens and pending PKCE live in memory;
 * only UOA's rotating refresh token and its client id persist, through [UOACredentials].
 */
object UOAAccount {
    data class Profile(
        val subject: String,
        val email: String,
        val name: String?,
    )

    data class State(
        val profile: Profile? = null,
        val avatar: ByteArray? = null,
        val signingIn: Boolean = false,
        val error: String? = null,
    )

    private data class Attempt(
        val id: UUID,
        val authorization: UOAAuthorization,
        val clientId: String,
    )

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private val transport = UOATransport()
    private val mutableState = MutableStateFlow(State())
    val state = mutableState.asStateFlow()
    private var generation = UUID.randomUUID()
    private var attempt: Attempt? = null
    private var lifetime: Job? = null
    private var credentials: UOACredentials? = null
    private var host = WeakReference<MainActivity>(null)
    private var appContext: Context? = null
    private var pendingUrl: String? = null
    private var loginOpen = false

    fun attach(activity: MainActivity) {
        host = WeakReference(activity)
        appContext = activity.applicationContext
        if (credentials == null) {
            credentials = UOACredentials(UOASecretSessionStorage(SecretStore.get(activity)), transport::request)
            restoreSession()
        }
        openPendingLogin()
    }

    fun detach(activity: MainActivity) {
        if (host.get() === activity) host.clear()
    }

    /** The in-app login shares the tabs' WebView profile, so the Google session reaches every tab. */
    private fun openPendingLogin() {
        val url = pendingUrl ?: return
        val activity = liveHost() ?: return
        pendingUrl = null
        loginOpen = true
        activity.openAccountLogin(url, generation.toString())
    }

    fun finishLogin(
        resultCode: Int,
        callback: String?,
        nonce: String?,
    ) {
        if (nonce != generation.toString()) return
        loginOpen = false
        when (val outcome = AccountLoginPolicy.outcome(resultCode, callback)) {
            is AccountLoginPolicy.Outcome.Callback -> receiveCallback(outcome.url)
            AccountLoginPolicy.Outcome.WebViewUnavailable -> openInBrowser()
            AccountLoginPolicy.Outcome.Cancelled -> signOut()
        }
    }

    /** Last resort when no WebView can be created; the callback returns via [AccountCallbackActivity]. */
    private fun openInBrowser() {
        val pending = attempt ?: return
        val intent =
            Intent(Intent.ACTION_VIEW, Uri.parse(pending.authorization.url(pending.clientId)))
                .addCategory(Intent.CATEGORY_BROWSABLE)
        val activity = liveHost() ?: return fail("Could not open login. Please try again.")
        try {
            activity.startActivity(intent)
        } catch (_: android.content.ActivityNotFoundException) {
            fail("Could not open login. Please try again.")
        }
    }

    private fun liveHost(): MainActivity? = host.get()?.takeUnless { it.isFinishing || it.isDestroyed }

    /** Restores the persisted session at launch without opening a login page. */
    private fun restoreSession() {
        val tokens = credentials ?: return
        if (!tokens.hasStoredSession()) return
        val current = begin()
        scope.launch { resume(tokens, current, fallback = false) }
    }

    fun signIn() {
        if (state.value.signingIn || state.value.profile != null) return
        val current = begin()
        scope.launch {
            val tokens = credentials
            if (tokens != null && tokens.hasStoredSession() && !resume(tokens, current, fallback = true)) return@launch
            authorize(current)
        }
    }

    private fun begin(): UUID {
        val current = UUID.randomUUID()
        generation = current
        mutableState.value = State(signingIn = true)
        return current
    }

    /** Returns true only when UOA rejected the stored session and interactive login should follow. */
    private suspend fun resume(
        tokens: UOACredentials,
        current: UUID,
        fallback: Boolean,
    ): Boolean {
        if (generation != current) return false
        val outcome = tokens.resume()
        if (generation != current) return false
        when (outcome) {
            UOACredentials.Resume.REJECTED -> {
                if (fallback) return true
                fail(UOATransport.Failure(401).message.orEmpty())
            }
            UOACredentials.Resume.UNAVAILABLE -> unavailable()
            UOACredentials.Resume.RESTORED ->
                try {
                    finishSignIn(current)
                } catch (_: Exception) {
                    if (generation == current) unavailable()
                }
        }
        return false
    }

    /** A failure in transit keeps the stored session for the next login or launch. */
    private fun unavailable() {
        reset(clearStorage = false)
        mutableState.value = State(error = "Could not restore your login. Please try again.")
    }

    private suspend fun authorize(current: UUID) {
        try {
            val body =
                buildJsonObject {
                    put("app_id", "com.unlikeotherai.kelpie")
                    put("client_name", "Kelpie for Android")
                    put("redirect_uris", JsonArray(listOf(JsonPrimitive(UOAAuthorization.CALLBACK))))
                    put("token_endpoint_auth_method", "none")
                    put("scope", UOAAuthorization.SCOPES)
                }
            val client =
                transport
                    .request("/oauth/register", "POST", body = body.toString())
                    .json()["client_id"]!!
                    .jsonPrimitive.content
            if (generation != current) return
            val auth = UOAAuthorization()
            attempt = Attempt(current, auth, client)
            pendingUrl = auth.url(client)
            openPendingLogin()
            lifetime?.cancel()
            lifetime =
                scope.launch {
                    delay(5 * 60 * 1000L)
                    if (generation == current && state.value.signingIn) fail("Login expired. Please try again.")
                }
        } catch (_: Exception) {
            if (generation == current) fail("Could not open login. Please try again.")
        }
    }

    fun receiveCallback(callback: String) {
        val pending =
            attempt ?: run {
                mutableState.value = state.value.copy(error = "Login expired. Please try again.")
                return
            }
        if (runCatching { pending.authorization.denied(callback) }.getOrDefault(false)) {
            fail("Login was cancelled.")
            return
        }
        val code = runCatching { pending.authorization.code(callback) }.getOrNull() ?: return
        val tokens = credentials ?: return
        attempt = null // A callback may be exchanged only once.
        lifetime?.cancel()
        scope.launch {
            try {
                val body =
                    buildJsonObject {
                        put("grant_type", "authorization_code")
                        put("code", code)
                        put("client_id", pending.clientId)
                        put("redirect_uri", UOAAuthorization.CALLBACK)
                        put("code_verifier", pending.authorization.verifier)
                    }
                val grant = UOATokenGrant.parse(transport.request("/oauth/token", "POST", body = body.toString()))
                if (generation != pending.id) return@launch
                tokens.accept(grant, pending.clientId)
                finishSignIn(pending.id)
            } catch (_: Exception) {
                if (generation == pending.id) fail("Login could not be completed. Please try again.")
            }
        }
    }

    /** Loads the UOA profile and switches favourites once a valid access token exists. */
    private suspend fun finishSignIn(current: UUID) {
        val identity = request("/oauth/me").json()
        if (generation != current) return
        val profile = Profile(identity["sub"]!!.jsonPrimitive.content, identity["email"]?.jsonPrimitive?.content.orEmpty(), identity["name"]?.jsonPrimitive?.contentOrNull)
        mutableState.value = State(profile = profile)
        BookmarkStore.useAccount()
        scheduleExpiry(current)
        val avatar = runCatching { request("/oauth/me/avatar").data }.getOrNull()
        if (generation == current) mutableState.value = state.value.copy(avatar = avatar)
    }

    /** Only memory-only sessions (no refresh token issued) end when the access token expires. */
    private fun scheduleExpiry(current: UUID) {
        val tokens = credentials ?: return
        if (tokens.persistent) return
        lifetime =
            scope.launch {
                delay((tokens.expiresAt - System.currentTimeMillis()).coerceAtLeast(0))
                if (generation == current) fail("Your session expired. Please log in again.")
            }
    }

    fun signOut() {
        val dropped = reset(clearStorage = true) ?: return
        val tokens = credentials ?: return
        scope.launch { tokens.revoke(dropped) }
    }

    /** Returns to the signed-out state. Storage survives only a restore that failed in transit. */
    private fun reset(clearStorage: Boolean): UOAStoredSession? {
        if (loginOpen) appContext?.sendBroadcast(Intent(AccountLoginActivity.CANCEL).setPackage(appContext?.packageName).putExtra("nonce", generation.toString()))
        loginOpen = false
        pendingUrl = null
        generation = UUID.randomUUID()
        attempt = null
        lifetime?.cancel()
        lifetime = null
        val dropped = credentials?.reset(clearStorage)
        mutableState.value = State()
        BookmarkStore.useLocalBookmarks()
        return dropped
    }

    private fun fail(message: String) {
        signOut()
        mutableState.value = State(error = message)
    }

    fun dismissError() {
        mutableState.value = state.value.copy(error = null)
    }

    suspend fun request(
        path: String,
        method: String = "GET",
        body: String? = null,
        version: String? = null,
    ): UOATransport.Response {
        val tokens = credentials?.takeIf { it.active } ?: throw UOATransport.Failure(401)
        val current = generation
        val expected = tokens.generation
        try {
            val token = tokens.validToken(expected)
            return try {
                send(path, method, token, body, version, current)
            } catch (failure: UOATransport.Failure) {
                if (failure.status != 401 || !tokens.persistent) throw failure
                // UOA refused the access token early; rotate once and retry this request.
                send(path, method, tokens.refresh(token, expected), body, version, current)
            }
        } catch (_: UOASessionRejected) {
            if (current == generation) fail(UOATransport.Failure(401).message.orEmpty())
            throw UOATransport.Failure(401)
        } catch (error: UOATransport.Failure) {
            if (error.status == 401 && current == generation) fail(error.message.orEmpty())
            throw error
        }
    }

    private suspend fun send(
        path: String,
        method: String,
        token: String,
        body: String?,
        version: String?,
        current: UUID,
    ): UOATransport.Response {
        val result = transport.request(path, method, token, body, version)
        if (generation != current) throw kotlinx.coroutines.CancellationException()
        return result
    }
}
