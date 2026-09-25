package com.kelpie.browser.account

import android.content.Context
import android.content.Intent
import android.net.Uri
import com.kelpie.browser.MainActivity
import com.kelpie.browser.browser.BookmarkStore
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
import kotlinx.serialization.json.long
import kotlinx.serialization.json.put
import java.lang.ref.WeakReference
import java.util.UUID

/** Application-scoped coordinator. Tokens, profile, avatar and pending PKCE live in memory. */
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
    private var token: String? = null
    private var expiresAt = 0L
    private var host = WeakReference<MainActivity>(null)
    private var appContext: Context? = null
    private var pendingUrl: String? = null
    private var fallbackOpen = false

    fun attach(activity: MainActivity) {
        host = WeakReference(activity)
        appContext = activity.applicationContext
        openPendingLogin()
    }

    fun detach(activity: MainActivity) {
        if (host.get() === activity) host.clear()
    }

    private fun openPendingLogin() {
        val url = pendingUrl ?: return
        val activity = host.get()?.takeUnless { it.isFinishing || it.isDestroyed } ?: return
        pendingUrl = null
        val intent = Intent(Intent.ACTION_VIEW, Uri.parse(url)).addCategory(Intent.CATEGORY_BROWSABLE)
        val handler = activity.packageManager.resolveActivity(intent, android.content.pm.PackageManager.MATCH_DEFAULT_ONLY)
        if (handler != null && handler.activityInfo.packageName != activity.packageName) {
            try {
                activity.startActivity(intent)
                return
            } catch (_: android.content.ActivityNotFoundException) {
            }
        }
        fallbackOpen = true
        activity.openAccountFallback(url, generation.toString())
    }

    fun finishFallback(
        callback: String?,
        nonce: String?,
    ) {
        if (nonce != generation.toString()) return
        fallbackOpen = false
        if (callback == null) signOut() else receiveCallback(callback)
    }

    fun signIn() {
        if (state.value.signingIn) return
        val current = UUID.randomUUID()
        generation = current
        mutableState.value = State(signingIn = true)
        scope.launch {
            try {
                val client =
                    run {
                        val body =
                            buildJsonObject {
                                put("client_name", "Kelpie for Android")
                                put("redirect_uris", JsonArray(listOf(JsonPrimitive(UOAAuthorization.CALLBACK))))
                                put("token_endpoint_auth_method", "none")
                                put("scope", UOAAuthorization.SCOPES)
                            }
                        transport
                            .request("/oauth/register", "POST", body = body.toString())
                            .json()["client_id"]!!
                            .jsonPrimitive.content
                    }
                if (generation != current) return@launch
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
                val response = transport.request("/oauth/token", "POST", body = body.toString()).json()
                if (generation != pending.id) return@launch
                val duration =
                    response["expires_in"]!!
                        .jsonPrimitive.long
                        .coerceAtMost(86400)
                        .also { require(it > 0) }
                token = response["access_token"]!!.jsonPrimitive.content
                expiresAt = System.currentTimeMillis() + duration * 1000
                val identity = request("/oauth/me").json()
                if (generation != pending.id) return@launch
                val profile = Profile(identity["sub"]!!.jsonPrimitive.content, identity["email"]?.jsonPrimitive?.content.orEmpty(), identity["name"]?.jsonPrimitive?.contentOrNull)
                mutableState.value = State(profile = profile)
                BookmarkStore.useAccount()
                lifetime =
                    scope.launch {
                        delay((expiresAt - System.currentTimeMillis()).coerceAtLeast(0))
                        if (generation == pending.id) fail("Your session expired. Please log in again.")
                    }
                val avatar = runCatching { request("/oauth/me/avatar").data }.getOrNull()
                if (generation == pending.id) mutableState.value = state.value.copy(avatar = avatar)
            } catch (_: Exception) {
                if (generation == pending.id) fail("Login could not be completed. Please try again.")
            }
        }
    }

    fun signOut() {
        if (fallbackOpen) appContext?.sendBroadcast(Intent(AccountLoginActivity.CANCEL).setPackage(appContext?.packageName).putExtra("nonce", generation.toString()))
        fallbackOpen = false
        pendingUrl = null
        generation = UUID.randomUUID()
        attempt = null
        lifetime?.cancel()
        lifetime = null
        token = null
        expiresAt = 0
        mutableState.value = State()
        BookmarkStore.useLocalBookmarks()
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
        val credential = token?.takeIf { expiresAt > System.currentTimeMillis() } ?: throw UOATransport.Failure(401)
        val current = generation
        try {
            val result = transport.request(path, method, credential, body, version)
            if (generation != current) throw kotlinx.coroutines.CancellationException()
            return result
        } catch (error: UOATransport.Failure) {
            if (error.status == 401 && current == generation) fail(error.message.orEmpty())
            throw error
        }
    }
}
