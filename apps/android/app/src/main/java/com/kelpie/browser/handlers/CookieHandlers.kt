package com.kelpie.browser.handlers

import android.webkit.CookieManager
import com.kelpie.browser.network.errorResponse
import com.kelpie.browser.network.successResponse
import java.net.URI

/**
 * Cookie handlers that use Android's [CookieManager] so that HttpOnly/Secure
 * cookies set by the server are visible to the API (unlike `document.cookie`,
 * which silently omits them).
 *
 * Note: Android does not surface HttpOnly/Secure/SameSite/expires metadata on
 * the cookies it stores — only the Set-Cookie header is consumed. The shape we
 * return matches [CookieInfo] in shared/api-types.ts; the metadata fields are
 * best-effort and may be defaults.
 */
class CookieHandlers(
    private val ctx: HandlerContext,
) {
    fun getCookies(body: Map<String, Any?>): Map<String, Any?> {
        val nameFilter = body["name"] as? String
        val url = body["url"] as? String ?: defaultCookieUrl()
        val raw = CookieManager.getInstance().getCookie(url).orEmpty()
        val host = hostFromUrl(url) ?: ""
        val parsed = parseCookieHeader(raw, defaultDomain = host)
        val filtered = if (nameFilter != null) parsed.filter { it["name"] == nameFilter } else parsed
        return successResponse(mapOf("cookies" to filtered, "count" to filtered.size))
    }

    fun setCookie(body: Map<String, Any?>): Map<String, Any?> {
        val name = body["name"] as? String ?: return errorResponse("MISSING_PARAM", "name required")
        val value = body["value"] as? String ?: return errorResponse("MISSING_PARAM", "value required")
        val path = body["path"] as? String ?: "/"
        val domain = body["domain"] as? String
        val httpOnly = body["httpOnly"] as? Boolean ?: false
        val secure = body["secure"] as? Boolean ?: false
        val sameSite = body["sameSite"] as? String
        val expires = body["expires"] as? String

        val attrs =
            buildList {
                add("Path=$path")
                if (domain != null) add("Domain=$domain")
                if (expires != null) add("Expires=$expires")
                if (secure) add("Secure")
                if (httpOnly) add("HttpOnly")
                if (sameSite != null) add("SameSite=$sameSite")
            }
        val header = (listOf("$name=$value") + attrs).joinToString("; ")
        val url = body["url"] as? String ?: currentPageUrl() ?: domain?.let { "http://$it/" } ?: "http://localhost/"
        val cm = CookieManager.getInstance()
        cm.setCookie(url, header)
        cm.flush()
        return successResponse()
    }

    fun deleteCookies(body: Map<String, Any?>): Map<String, Any?> {
        val deleteAll = body["deleteAll"] as? Boolean ?: false
        val nameFilter = body["name"] as? String
        val domainFilter = body["domain"] as? String
        val cm = CookieManager.getInstance()
        val url = body["url"] as? String ?: defaultCookieUrl()
        val host = hostFromUrl(url) ?: ""
        val existing = parseCookieHeader(cm.getCookie(url).orEmpty(), defaultDomain = host)

        if (deleteAll && nameFilter == null && domainFilter == null) {
            val pending = existing.size
            cm.removeAllCookies(null)
            cm.flush()
            return successResponse(mapOf("deleted" to pending))
        }

        val removed =
            existing.filter { cookie ->
                val matchesName = nameFilter == null || cookie["name"] == nameFilter
                val matchesDomain = domainFilter == null || cookie["domain"] == domainFilter
                matchesName && matchesDomain
            }
        val expiredAttr = "Expires=Thu, 01 Jan 1970 00:00:00 GMT"
        for (cookie in removed) {
            val name = cookie["name"] as? String ?: continue
            val path = cookie["path"] as? String ?: "/"
            val cookieDomain = cookie["domain"] as? String
            val attrs =
                buildList {
                    add("Path=$path")
                    if (!cookieDomain.isNullOrEmpty()) add("Domain=$cookieDomain")
                    add(expiredAttr)
                }
            cm.setCookie(url, (listOf("$name=") + attrs).joinToString("; "))
        }
        cm.flush()
        return successResponse(mapOf("deleted" to removed.size))
    }

    private fun currentPageUrl(): String? = ctx.webView?.url

    private fun defaultCookieUrl(): String = currentPageUrl() ?: "http://localhost/"

    private fun hostFromUrl(url: String?): String? =
        try {
            url?.let { URI(it).host }
        } catch (_: Exception) {
            null
        }

    private fun parseCookieHeader(
        header: String,
        defaultDomain: String,
    ): List<Map<String, Any?>> {
        if (header.isBlank()) return emptyList()
        return header
            .split(";")
            .mapNotNull { rawPair ->
                val pair = rawPair.trim()
                if (pair.isEmpty()) return@mapNotNull null
                val eq = pair.indexOf('=')
                val (name, value) =
                    if (eq < 0) {
                        pair to ""
                    } else {
                        pair.substring(0, eq).trim() to pair.substring(eq + 1).trim()
                    }
                if (name.isEmpty()) return@mapNotNull null
                mapOf<String, Any?>(
                    "name" to name,
                    "value" to value,
                    "domain" to defaultDomain,
                    "path" to "/",
                    "expires" to null,
                    "httpOnly" to false,
                    "secure" to false,
                    "sameSite" to "",
                )
            }
    }
}
