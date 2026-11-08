package com.kelpie.browser.browser

import android.content.Context
import android.content.SharedPreferences
import android.webkit.CookieManager
import android.webkit.WebView
import androidx.webkit.ProfileStore
import androidx.webkit.WebViewCompat
import androidx.webkit.WebViewFeature
import com.kelpie.browser.network.errorResponse
import com.kelpie.browser.network.successResponse
import java.util.UUID

/** Main-thread registry. A generation UUID separates a retired profile from a reused public name. */
object PartitionRegistry {
    private lateinit var prefs: SharedPreferences
    private const val PREFIX = "partition:"
    private const val PENDING = "pendingDeletion"
    private val profileName = Regex("kelpie-[0-9a-f-]{36}")

    class Failure(
        val code: String,
        override val message: String,
    ) : Exception(message) {
        fun response(): Map<String, Any?> = errorResponse(code, message)
    }

    data class Options(
        val partition: String?,
        val name: String?,
    )

    fun validate(body: Map<String, Any?>): Options {
        if (body.containsKey("partition") && body["partition"] !is String) {
            throw Failure("INVALID_PARTITION", "partition must be a string")
        }
        if (body.containsKey("persistent") && body["persistent"] !is Boolean) {
            throw Failure("INVALID_PARAM", "persistent must be a boolean")
        }
        if (body.containsKey("name") && body["name"] !is String) throw Failure("INVALID_PARAM", "name must be a string")
        val name = body["name"] as? String
        if (name != null && name.length > 200) throw Failure("INVALID_PARAM", "name must be at most 200 characters")
        val id = body["partition"] as? String
        if (id != null) {
            validateId(id)
            if (body["persistent"] == false) throw Failure("PARTITION_UNSUPPORTED", "Mobile partitions require persistent:true")
        }
        return Options(id, name)
    }

    fun validateId(id: String) {
        if (!Regex("[A-Za-z0-9._-]{1,128}").matches(id) ||
            id.none { it in 'A'..'Z' || it in 'a'..'z' || it in '0'..'9' } ||
            id.lowercase() in setOf("default", ".", "..") ||
            id.startsWith("ephemeral-")
        ) {
            throw Failure("INVALID_PARTITION", "Invalid partition identifier")
        }
    }

    /** Called from Application, before a login or tab can load a WebView profile. */
    fun initialize(context: Context) {
        if (::prefs.isInitialized) return
        prefs = context.getSharedPreferences("kelpie_partitions", Context.MODE_PRIVATE)
        if (supported()) pending().forEach { purge(it) }
    }

    fun supported(): Boolean = runCatching { WebViewFeature.isFeatureSupported(WebViewFeature.MULTI_PROFILE) }.getOrDefault(false)

    fun resolve(
        id: String,
        restoring: Boolean = false,
    ): String {
        validateId(id)
        if (!supported()) throw Failure("PARTITION_UNSUPPORTED", "Update Android System WebView: multiple profiles are unavailable")
        val stored = prefs.getString(PREFIX + id, null)
        if (stored != null) {
            if (!profileName.matches(stored) || stored in pending()) throw Failure("INVALID_PARTITION", "Unusable partition mapping")
            if (prefs.all.count { it.key.startsWith(PREFIX) && it.value == stored } != 1) {
                throw Failure("INVALID_PARTITION", "Duplicate partition mapping")
            }
            return stored
        }
        if (restoring) throw Failure("INVALID_PARTITION", "Saved partition has no website store mapping")
        val created = "kelpie-${UUID.randomUUID()}"
        check(prefs.edit().putString(PREFIX + id, created).commit()) { "Could not save partition mapping" }
        return created
    }

    fun bind(
        view: WebView,
        profile: String?,
    ) {
        val actual =
            profile ?: if (com.kelpie.browser.KelpieEnvironment
                    .standalone(view.context)
            ) {
                null
            } else {
                "com.unlikeotherai.kelpie.browser.${com.kelpie.browser.KelpieEnvironment.profileID}"
            }
        if (actual != null) {
            if (!supported()) throw Failure("PARTITION_UNSUPPORTED", "Update Android System WebView: multiple profiles are unavailable")
            WebViewCompat.setProfile(view, actual)
        }
    }

    fun cookies(view: WebView): CookieManager = if (supported()) WebViewCompat.getProfile(view).cookieManager else CookieManager.getInstance()

    fun listing(tabs: List<BrowserTab>): List<Map<String, Any?>> {
        val active =
            prefs.all.keys.filter { it.startsWith(PREFIX) }.sorted().map { key ->
                val id = key.removePrefix(PREFIX)
                mapOf<String, Any?>("id" to id, "persistent" to true, "tabCount" to tabs.count { it.partition == id })
            }
        return active +
            pending().sorted().map {
                mapOf("id" to "orphan:$it", "persistent" to true, "tabCount" to 0)
            }
    }

    fun delete(
        id: String,
        tabs: TabStore,
    ): Map<String, Any?> {
        if (!supported()) return errorResponse("PARTITION_UNSUPPORTED", "Multiple WebView profiles are unavailable")
        val orphan = id.removePrefix("orphan:").takeIf { id.startsWith("orphan:") && it in pending() }
        val profile =
            orphan ?: prefs.getString(PREFIX + id, null)
                ?: return successResponse(mapOf("deleted" to id, "existed" to false, "tabsClosed" to 0))
        if (!profileName.matches(profile)) return errorResponse("INVALID_PARTITION", "Unusable partition mapping")
        // Commit retirement before closing views; a crash cannot restore this identity under the old name.
        check(
            prefs
                .edit()
                .remove(PREFIX + id)
                .putStringSet(PENDING, pending() + profile)
                .commit(),
        )
        val closing =
            tabs.tabs.value
                .filter { it.partition == id }
                .map { it.id }
        closing.forEach(tabs::closeTab)
        return if (purge(profile)) {
            successResponse(mapOf("deleted" to id, "existed" to true, "tabsClosed" to closing.size))
        } else {
            errorResponse("PARTITION_IN_USE", "WebView retains this profile until restart; pending deletion is listed as orphan:$profile") +
                mapOf("tabsClosed" to closing.size, "existed" to true)
        }
    }

    private fun pending(): Set<String> = prefs.getStringSet(PENDING, emptySet()).orEmpty().toSet()

    private fun purge(profile: String): Boolean {
        if (!profileName.matches(profile)) return false
        return try {
            ProfileStore.getInstance().deleteProfile(profile)
            check(prefs.edit().putStringSet(PENDING, pending() - profile).commit())
            true
        } catch (_: RuntimeException) {
            false
        }
    }
}
