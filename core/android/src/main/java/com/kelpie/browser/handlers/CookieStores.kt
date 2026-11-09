package com.kelpie.browser.handlers

import android.webkit.CookieManager
import androidx.webkit.ProfileStore
import com.kelpie.browser.KelpieEnvironment
import com.kelpie.browser.browser.PartitionRegistry
import com.kelpie.browser.network.errorResponse
import com.kelpie.browser.sync.CookieSync
import com.kelpie.browser.sync.SetCookieLine
import java.time.Instant
import java.time.ZoneOffset
import java.time.format.DateTimeFormatter

/**
 * Cookie stores the automation API can name: the default store (no target), a
 * tab (`tabId`) or a partition (`partition`). Main thread only.
 */
internal class CookieStores(
    private val ctx: HandlerContext,
) {
    /** One resolved store. [identity] tells two targets apart; [page] is the tab's current URL. */
    class Store(
        val manager: CookieManager,
        val identity: String,
        val page: String?,
    )

    class Refusal(
        val response: Map<String, Any?>,
    ) : Exception(response.toString())

    /**
     * Resolves [body]'s target. [currentPage]: with no target, use the visible
     * tab (plain `get-cookies`). [create]: a write may create a partition's store.
     */
    fun resolve(
        body: Map<*, *>,
        create: Boolean,
        currentPage: Boolean = false,
    ): Store {
        val tabId = body["tabId"]
        val partition = body["partition"]
        if (tabId != null && tabId !is String) throw refusal("INVALID_PARAMS", "tabId must be a string")
        if (partition != null && partition !is String) throw refusal("INVALID_PARTITION", "partition must be a string")
        if (tabId != null && partition != null) throw refusal("INVALID_PARAMS", "Use tabId or partition, not both")
        if (tabId is String) {
            val tab =
                ctx.tabStore
                    ?.tabs
                    ?.value
                    ?.firstOrNull { it.id == tabId } ?: throw refusal("TAB_NOT_FOUND", "No tab with id $tabId")
            return Store(PartitionRegistry.cookies(tab.webView), tab.partition?.let { "partition:$it" } ?: DEFAULT, tab.webView.url)
        }
        if (partition is String) return partitionStore(partition, create)
        if (currentPage) {
            val view = ctx.webView ?: throw refusal("NO_WEBVIEW", "No target WebView")
            val tab =
                ctx.tabStore
                    ?.tabs
                    ?.value
                    ?.firstOrNull { it.webView === view }
            return Store(PartitionRegistry.cookies(view), tab?.partition?.let { "partition:$it" } ?: DEFAULT, view.url)
        }
        return Store(defaultManager(), DEFAULT, null)
    }

    private fun partitionStore(
        id: String,
        create: Boolean,
    ): Store {
        try {
            PartitionRegistry.validateId(id)
            if (!PartitionRegistry.supported()) throw refusal("PARTITION_UNSUPPORTED", "Update Android System WebView: multiple profiles are unavailable")
            val profile = PartitionRegistry.resolve(id, restoring = !create)
            return Store(ProfileStore.getInstance().getOrCreateProfile(profile).cookieManager, "partition:$id", null)
        } catch (failure: PartitionRegistry.Failure) {
            throw Refusal(failure.response())
        }
    }

    /** Kelpie's default store: the WebView default profile standalone, the host's private profile embedded. */
    private fun defaultManager(): CookieManager {
        if (KelpieEnvironment.standalone(KelpieEnvironment.app) || !PartitionRegistry.supported()) return CookieManager.getInstance()
        return ProfileStore
            .getInstance()
            .getOrCreateProfile("com.unlikeotherai.kelpie.browser.${KelpieEnvironment.profileID}")
            .cookieManager
    }

    /** Every cookie [store] returns for [urls], deduplicated by identity; partitioned and undescribable ones are counted. */
    fun read(
        store: Store,
        urls: List<String>,
    ): Pair<List<SetCookieLine.Parsed>, Int> {
        val engine = CookieSync.ManagerEngine(store.manager)
        val found = linkedMapOf<Triple<String, String, String>, SetCookieLine.Parsed>()
        var skipped = 0
        for (url in urls.distinct()) {
            for (line in engine.info(url)) {
                val parsed = SetCookieLine.parse(line)
                if (parsed == null || parsed.partitioned) {
                    skipped++
                    continue
                }
                found[Triple(parsed.domain, parsed.path, parsed.name)] = parsed
            }
        }
        return found.values.toList() to skipped
    }

    /** Writes [cookies] and returns the indexes the engine did not keep. */
    fun write(
        store: Store,
        cookies: List<SetCookieLine.Parsed>,
    ): List<Int> {
        for (cookie in cookies) store.manager.setCookie(SetCookieLine.url(cookie.domain, cookie.path), SetCookieLine.forWrite(cookie.wire()))
        store.manager.flush()
        val engine = CookieSync.ManagerEngine(store.manager)
        return cookies.indices.filter { index ->
            val cookie = cookies[index]
            val lines = runCatching { engine.info(SetCookieLine.url(cookie.domain, cookie.path)) }.getOrDefault(emptyList())
            lines.mapNotNull(SetCookieLine::parse).none {
                it.domain == cookie.domain && it.path == cookie.path && it.name == cookie.name && it.value == cookie.value
            }
        }
    }

    companion object {
        const val DEFAULT = "default"
        private val DOMAIN = Regex("""\.?[a-z0-9_\-\[\]:.]+""")
        private val iso = DateTimeFormatter.ofPattern("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'").withZone(ZoneOffset.UTC)

        fun refusal(
            code: String,
            message: String,
        ) = Refusal(errorResponse(code, message))

        /** The cookie's host equals [domain] or is a subdomain of it; leading dots are ignored. */
        fun inDomain(
            cookieDomain: String,
            domain: String,
        ): Boolean {
            val host = cookieDomain.removePrefix(".").lowercase()
            val filter = domain.removePrefix(".").lowercase()
            return host == filter || host.endsWith(".$filter")
        }

        /** The `get-cookies` shape: ISO-8601 `expires`, four-valued `sameSite`. */
        fun api(cookie: SetCookieLine.Parsed): Map<String, Any?> =
            mapOf(
                "name" to cookie.name,
                "value" to cookie.value,
                "domain" to cookie.domain,
                "path" to cookie.path,
                "expires" to cookie.expires?.let { iso.format(Instant.ofEpochSecond(it)) },
                "httpOnly" to cookie.httpOnly,
                "secure" to cookie.secure,
                "sameSite" to cookie.sameSite,
            )

        /**
         * Parses one `set-cookies` entry. Every field is required; `expires` is
         * ISO-8601, whole Unix seconds or null. Returns null when malformed.
         */
        fun fromApi(value: Any?): SetCookieLine.Parsed? {
            val cookie = value as? Map<*, *> ?: return null
            val name = (cookie["name"] as? String)?.takeIf { it.isNotEmpty() } ?: return null
            val cookieValue = cookie["value"] as? String ?: return null
            val domain = (cookie["domain"] as? String)?.lowercase()?.takeIf { it.isNotEmpty() && it != "." } ?: return null
            val path = (cookie["path"] as? String)?.takeIf { it.startsWith("/") } ?: return null
            if (!cookie.containsKey("expires")) return null
            val expires =
                when (val raw = cookie["expires"]) {
                    null -> null
                    is Number -> raw.toLong()
                    is String -> runCatching { Instant.parse(raw).epochSecond }.getOrNull() ?: return null
                    else -> return null
                }
            val httpOnly = cookie["httpOnly"] as? Boolean ?: return null
            val secure = cookie["secure"] as? Boolean ?: return null
            val sameSite = (cookie["sameSite"] as? String)?.takeIf { it in setOf("Strict", "Lax", "None", "Unspecified") } ?: return null
            // Nothing may smuggle an attribute into the Set-Cookie line.
            if (name.any { it == ';' || it == '=' || it < ' ' } || cookieValue.any { it == ';' || it < ' ' }) return null
            if (!domain.matches(DOMAIN) || path.any { it == ';' || it < ' ' }) return null
            return SetCookieLine.Parsed(domain, path, name, cookieValue, expires, secure, httpOnly, sameSite, partitioned = false)
        }
    }
}
