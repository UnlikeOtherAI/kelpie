package com.kelpie.browser.browser

import android.content.Intent
import android.net.Uri
import java.net.URISyntaxException

/** Links a WebView cannot load itself, such as `slack:`, `mailto:` or `intent:`. */
internal object ExternalAppLinks {
    private val webSchemes = setOf("http", "https", "about", "data", "blob", "file", "javascript", "content")
    private val refusedDataSchemes = setOf("file", "content", "javascript")

    fun isAppLink(uri: Uri): Boolean {
        val scheme = uri.scheme?.lowercase() ?: return false
        return scheme.isNotEmpty() && scheme !in webSchemes
    }

    /**
     * Rebuilds a link as a clean VIEW intent: its data URI, an optional target package and the
     * BROWSABLE category. Components, selectors, extras and flags from an `intent:` URL are never
     * forwarded, and data URIs that would expose local files are refused.
     */
    fun intentFor(url: String): Intent? {
        if (!url.startsWith("intent:", ignoreCase = true)) {
            return Intent(Intent.ACTION_VIEW, Uri.parse(url)).addCategory(Intent.CATEGORY_BROWSABLE)
        }
        val parsed = parseIntent(url) ?: return null
        val data = parsed.data
        if (data?.scheme?.lowercase() in refusedDataSchemes) return null
        if (data == null && parsed.`package` == null) return null
        return Intent(Intent.ACTION_VIEW).apply {
            this.data = data
            `package` = parsed.`package`
            addCategory(Intent.CATEGORY_BROWSABLE)
        }
    }

    /** The web page an `intent:` link offers when no app can open it. */
    fun fallbackUrl(url: String): String? {
        if (!url.startsWith("intent:", ignoreCase = true)) return null
        val fallback = parseIntent(url)?.getStringExtra("browser_fallback_url") ?: return null
        val scheme = Uri.parse(fallback).scheme?.lowercase()
        return fallback.takeIf { scheme == "https" || scheme == "http" }
    }

    /** `scheme://host[:port]` for an http(s) page, otherwise null. */
    fun origin(url: String?): String? {
        val uri = url?.let(Uri::parse) ?: return null
        val scheme = uri.scheme?.lowercase()
        val host = uri.host ?: return null
        if (scheme != "https" && scheme != "http") return null
        val port = if (uri.port == -1) "" else ":${uri.port}"
        return "$scheme://${host.lowercase()}$port"
    }

    private fun parseIntent(url: String): Intent? =
        try {
            Intent.parseUri(url, Intent.URI_INTENT_SCHEME)
        } catch (_: URISyntaxException) {
            null
        }
}
