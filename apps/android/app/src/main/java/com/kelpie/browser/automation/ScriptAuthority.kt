package com.kelpie.browser.automation

import kotlinx.coroutines.currentCoroutineContext
import kotlin.coroutines.AbstractCoroutineContextElement
import kotlin.coroutines.CoroutineContext

/** In-memory authorization reference only. No profile, bearer or new identity store. */
class ScriptOwner(
    private val principal: String,
    private val grant: String,
    private val listener: String,
) {
    override fun equals(other: Any?): Boolean = other is ScriptOwner && principal == other.principal && grant == other.grant && listener == other.listener

    override fun hashCode(): Int = 31 * (31 * principal.hashCode() + grant.hashCode()) + listener.hashCode()

    override fun toString(): String = "ScriptOwner"
}

/** Created by the existing transport authorization, never by request body fields. */
class ScriptAuthority(
    val owner: ScriptOwner,
    private val synchronous: () -> Boolean = { true },
    private val current: suspend () -> Boolean,
) : AbstractCoroutineContextElement(Key) {
    companion object Key : CoroutineContext.Key<ScriptAuthority>

    suspend fun permits(): Boolean =
        try {
            current()
        } catch (_: Exception) {
            false
        }

    /** Callback/dispatch fence; transport supplies a current local grant check. */
    fun permitsOnMain(): Boolean = synchronous()

    suspend fun requireCurrent() {
        if (!permits()) throw ScriptFailure("SCRIPT_AUTHORIZATION_REVOKED")
    }
}

suspend fun currentScriptAuthority(): ScriptAuthority =
    currentCoroutineContext()[ScriptAuthority]?.also { it.requireCurrent() }
        ?: throw ScriptFailure("SCRIPT_AUTHORIZATION_REQUIRED")

class ScriptFailure(
    val code: String,
    val mayHaveCompleted: Boolean = false,
) : RuntimeException(code)
