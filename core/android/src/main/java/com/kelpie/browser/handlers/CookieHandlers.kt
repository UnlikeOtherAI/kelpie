package com.kelpie.browser.handlers

import com.kelpie.browser.network.Router
import com.kelpie.browser.network.errorResponse
import com.kelpie.browser.network.successResponse
import com.kelpie.browser.sync.CookieSync
import com.kelpie.browser.sync.SetCookieLine

/**
 * Cookie endpoints over WebView's `CookieManager`, HttpOnly cookies included.
 * Reads use `CookieManagerCompat.getCookieInfo`, so every cookie carries its real
 * domain (leading dot = domain cookie), path, expiry, Secure, HttpOnly and SameSite.
 * WebView cannot enumerate a store: `all:true` reads every URL Kelpie knows
 * (sync metadata, history, recent pages) and reports `complete:false`.
 */
class CookieHandlers(
    private val ctx: HandlerContext,
) {
    private val stores = CookieStores(ctx)
    private val legacy = LegacyCookieHandlers(ctx)

    fun register(router: Router) {
        router.register("get-cookies") { getCookies(it) }
        router.register("set-cookie") { legacy.setCookie(it) }
        router.register("set-cookies") { setCookies(it) }
        router.register("copy-cookies") { copyCookies(it) }
        router.register("delete-cookies") { deleteCookies(it) }
        router.register("get-cookie-sync-status") { successResponse(CookieSync.status()) }
    }

    suspend fun getCookies(body: Map<String, Any?>): Map<String, Any?> {
        val all = body["all"] ?: false
        if (all !is Boolean) return errorResponse("INVALID_PARAMS", "all must be a boolean")
        val domain = body["domain"]
        if (domain != null && domain !is String) return errorResponse("INVALID_PARAMS", "domain must be a string")
        if (!CookieSync.supported()) return if (all) unsupported() else legacy.getCookies(body)
        return guarded {
            val store = stores.resolve(body, create = false, currentPage = !all)
            val url = body["url"] as? String
            val urls =
                when {
                    url != null -> listOf(url)
                    all -> knownUrls(store, domain as? String)
                    else -> listOf(store.page ?: "http://localhost/")
                }
            val (read, skipped) = stores.read(store, urls)
            val name = body["name"] as? String
            val cookies =
                read
                    .filter { name == null || it.name == name }
                    .filter { domain == null || CookieStores.inDomain(it.domain, domain as String) }
                    .map(CookieStores::api)
            successResponse(
                buildMap {
                    put("cookies", cookies)
                    put("count", cookies.size)
                    if (all) put("complete", false)
                    if (skipped > 0) put("skipped", skipped)
                },
            )
        }
    }

    /** Writes up to 500 cookies in the `get-cookies` shape; a malformed one fails the whole call first. */
    suspend fun setCookies(body: Map<String, Any?>): Map<String, Any?> {
        val items = body["cookies"] as? List<*>
        if (items == null || items.size > MAX_COOKIES_PER_WRITE) {
            return errorResponse("INVALID_PARAMS", "cookies must be an array of at most $MAX_COOKIES_PER_WRITE")
        }
        val cookies = items.map { CookieStores.fromApi(it) }
        val malformed = cookies.indexOfFirst { it == null }
        if (malformed >= 0) return errorResponse("INVALID_PARAMS", "cookies[$malformed] is not a complete cookie")
        if (!CookieSync.supported()) return unsupported()
        return guarded {
            val store = stores.resolve(body, create = true)
            val parsed = cookies.filterNotNull()
            val refused = stores.write(store, parsed)
            successResponse(
                mapOf(
                    "set" to parsed.size - refused.size,
                    "failed" to refused.map { mapOf("index" to it, "name" to parsed[it].name, "domain" to parsed[it].domain, "error" to "NOT_STORED") },
                ),
            )
        }
    }

    /** Copies cookies between two stores on this device; values never leave it. */
    suspend fun copyCookies(body: Map<String, Any?>): Map<String, Any?> {
        val from = body["from"] as? Map<*, *> ?: return errorResponse("INVALID_PARAMS", "from must be an object")
        val to = body["to"] as? Map<*, *> ?: return errorResponse("INVALID_PARAMS", "to must be an object")
        val domain = body["domain"]
        if (domain != null && domain !is String) return errorResponse("INVALID_PARAMS", "domain must be a string")
        if (!CookieSync.supported()) return unsupported()
        return guarded {
            val source = stores.resolve(from, create = false)
            val target = stores.resolve(to, create = true)
            if (source.identity == target.identity) return@guarded errorResponse("INVALID_PARAMS", "from and to are the same cookie store")
            val (read, _) = stores.read(source, knownUrls(source, domain as? String))
            val selected = read.filter { domain == null || CookieStores.inDomain(it.domain, domain as String) }
            val refused = stores.write(target, selected)
            successResponse(
                mapOf(
                    "copied" to selected.size - refused.size,
                    "failed" to refused.map { mapOf("name" to selected[it].name, "domain" to selected[it].domain, "error" to "NOT_STORED") },
                ),
            )
        }
    }

    /** `deleteCookies` on the current tab, matching the real domain and path of each cookie. */
    suspend fun deleteCookies(body: Map<String, Any?>): Map<String, Any?> {
        if (!CookieSync.supported()) return legacy.deleteCookies(body)
        val deleteAll = body["deleteAll"] as? Boolean ?: false
        val name = body["name"] as? String
        val domain = body["domain"] as? String
        if (!deleteAll && name == null && domain == null) return successResponse(mapOf("deleted" to 0))
        return guarded {
            val store = stores.resolve(body, create = false, currentPage = true)
            if (deleteAll && name == null && domain == null && body["url"] == null) {
                val (existing, _) = stores.read(store, listOf(store.page ?: "http://localhost/"))
                store.manager.removeAllCookies(null)
                store.manager.flush()
                return@guarded successResponse(mapOf("deleted" to existing.size))
            }
            val url = body["url"] as? String ?: store.page ?: "http://localhost/"
            val (existing, _) = stores.read(store, listOf(url))
            val doomed =
                existing.filter { cookie ->
                    (name == null || cookie.name == name) &&
                        (domain == null || cookie.domain.removePrefix(".").equals(domain.removePrefix("."), ignoreCase = true))
                }
            for (cookie in doomed) {
                store.manager.setCookie(SetCookieLine.url(cookie.domain, cookie.path), SetCookieLine.forDelete(cookie.domain, cookie.path, cookie.name))
            }
            store.manager.flush()
            successResponse(mapOf("deleted" to doomed.size))
        }
    }

    /** Every URL Kelpie knows for the default store, the target tab's page and the domain's root. */
    private suspend fun knownUrls(
        store: CookieStores.Store,
        domain: String?,
    ): List<String> =
        buildList {
            addAll(CookieSync.coverageUrls())
            store.page?.takeIf { it.startsWith("http") }?.let(::add)
            domain?.let { add(SetCookieLine.url(it.removePrefix("."))) }
        }

    private inline fun guarded(block: () -> Map<String, Any?>): Map<String, Any?> =
        try {
            block()
        } catch (refusal: CookieStores.Refusal) {
            refusal.response
        } catch (error: Exception) {
            errorResponse("COOKIE_ERROR", error.message ?: "Cookie store error")
        }

    private fun unsupported() = errorResponse("PLATFORM_NOT_SUPPORTED", "Update Android System WebView: cookie attributes are unavailable")

    private companion object {
        const val MAX_COOKIES_PER_WRITE = 500
    }
}
