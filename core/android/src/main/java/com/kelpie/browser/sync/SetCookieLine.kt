package com.kelpie.browser.sync

import java.time.Instant
import java.time.ZoneOffset
import java.time.ZonedDateTime
import java.time.format.DateTimeFormatter
import java.util.Locale

/**
 * Converts between WebView `getCookieInfo` lines and the sync wire shape.
 *
 * Chromium builds each line with `CanonicalCookie::BuildCookieAttributesLine`:
 * `name=value; domain=<d>; path=<p>[; expires=<HTTP date>][; secure][; httponly]
 * [; partitioned][; samesite=<v>]`. `domain` carries a leading dot only for a
 * domain cookie, which is how host-only and domain cookies stay distinct.
 */
object SetCookieLine {
    /** One parsed engine cookie in wire shape. */
    data class Parsed(
        val domain: String,
        val path: String,
        val name: String,
        val value: String,
        val expires: Long?,
        val secure: Boolean,
        val httpOnly: Boolean,
        val sameSite: String,
        val partitioned: Boolean,
    ) {
        val host: String get() = domain.removePrefix(".")

        fun wire(): Map<String, Any?> =
            mapOf(
                "domain" to domain,
                "path" to path,
                "name" to name,
                "value" to value,
                "expires" to expires,
                "secure" to secure,
                "httpOnly" to httpOnly,
                "sameSite" to sameSite,
            )
    }

    private val httpDate = DateTimeFormatter.RFC_1123_DATE_TIME.withLocale(Locale.US)

    /**
     * Parses one line. Returns null for anything sync cannot describe exactly:
     * no name, no domain or path, an unreadable expiry or an unknown SameSite.
     */
    fun parse(line: String): Parsed? {
        val parts = line.split(';')
        val pair = parts.first()
        val eq = pair.indexOf('=')
        if (eq <= 0) return null
        val name = pair.substring(0, eq).trim()
        val value = pair.substring(eq + 1).trim()
        if (name.isEmpty()) return null
        var domain: String? = null
        var path: String? = null
        var expires: Long? = null
        var secure = false
        var httpOnly = false
        var partitioned = false
        var sameSite = "Unspecified"
        for (raw in parts.drop(1)) {
            val attribute = raw.trim()
            if (attribute.isEmpty()) continue
            val split = attribute.indexOf('=')
            val key = (if (split < 0) attribute else attribute.substring(0, split)).trim().lowercase(Locale.US)
            val argument = if (split < 0) "" else attribute.substring(split + 1).trim()
            when (key) {
                "domain" -> domain = argument.lowercase(Locale.US).takeIf { it.isNotEmpty() && it != "." }
                "path" -> path = argument.takeIf { it.startsWith("/") }
                "expires" -> expires = parseExpiry(argument) ?: return null
                "max-age" -> return null // getCookieInfo reports absolute expiry; a relative one is undescribable
                "secure" -> secure = true
                "httponly" -> httpOnly = true
                "partitioned" -> partitioned = true
                "samesite" -> sameSite = sameSiteOf(argument) ?: return null
            }
        }
        return Parsed(
            domain = domain ?: return null,
            path = path ?: return null,
            name = name,
            value = value,
            expires = expires,
            secure = secure,
            httpOnly = httpOnly,
            sameSite = sameSite,
            partitioned = partitioned,
        )
    }

    private fun sameSiteOf(value: String): String? =
        when (value.lowercase(Locale.US)) {
            "strict" -> "Strict"
            "lax" -> "Lax"
            "none" -> "None"
            else -> null
        }

    private fun parseExpiry(value: String): Long? = runCatching { ZonedDateTime.parse(value, httpDate).toEpochSecond() }.getOrNull()

    fun formatExpiry(seconds: Long): String = httpDate.format(Instant.ofEpochSecond(seconds).atZone(ZoneOffset.UTC))

    /** The `Set-Cookie` value that writes [cookie] (wire shape) into the engine. */
    fun forWrite(cookie: Map<String, Any?>): String {
        val domain = cookie["domain"] as String
        return buildList {
            add("${cookie["name"]}=${cookie["value"] ?: ""}")
            if (domain.startsWith(".")) add("Domain=${domain.removePrefix(".")}")
            add("Path=${cookie["path"] ?: "/"}")
            (cookie["expires"] as? Number)?.let { add("Expires=${formatExpiry(it.toLong())}") }
            if (cookie["secure"] == true) add("Secure")
            if (cookie["httpOnly"] == true) add("HttpOnly")
            (cookie["sameSite"] as? String)?.takeIf { it != "Unspecified" }?.let { add("SameSite=$it") }
        }.joinToString("; ")
    }

    /** The `Set-Cookie` value that removes the cookie with this identity. */
    fun forDelete(
        domain: String,
        path: String,
        name: String,
    ): String =
        buildList {
            add("$name=")
            if (domain.startsWith(".")) add("Domain=${domain.removePrefix(".")}")
            add("Path=$path")
            add("Expires=Thu, 01 Jan 1970 00:00:00 GMT")
            // Writes go through https URLs, so Secure is allowed and covers __Secure-/__Host- names.
            add("Secure")
        }.joinToString("; ")

    /** `https://<host><path>` for a cookie domain and path; IPv6 hosts get brackets. */
    fun url(
        domain: String,
        path: String = "/",
    ): String {
        val host = domain.removePrefix(".")
        val authority = if (host.contains(':') && !host.startsWith("[")) "[$host]" else host
        return "https://$authority${if (path.startsWith("/")) path else "/"}"
    }
}
