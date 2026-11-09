package com.kelpie.browser.sync

import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put

/** The calls sync needs from one WebView cookie store; blocking, any thread. */
interface CookieInfoEngine {
    /** `CookieManagerCompat.getCookieInfo(url)`; throws when the query fails. */
    fun info(url: String): List<String>

    fun set(
        url: String,
        header: String,
    )

    fun flush()
}

/**
 * The Android cookie adapter for the default store. WebView cannot enumerate
 * cookies, so a read queries exact URLs and reports them as `{"urls":[…]}`
 * coverage: `https://<host><path>` for every metadata entry, plus history hosts
 * and recent page loads from unpartitioned tabs. Any failed query aborts the
 * read; it never turns into an empty result.
 */
class WebViewCookieSource(
    private val engine: CookieInfoEngine,
    private val historyHosts: () -> List<String>,
    private val recent: RecentLoads,
) : CookieSource {
    override fun snapshot(
        entries: List<EntryLocation>,
        hosts: Set<String>?,
    ): CookieSnapshot {
        val urls = CoverageUrls.build(entries, hosts, if (hosts == null) historyHosts() else emptyList(), recent.urls())
        val cookies = linkedMapOf<Triple<String, String, String>, SetCookieLine.Parsed>()
        for (url in urls) {
            val lines =
                try {
                    engine.info(url)
                } catch (error: Exception) {
                    throw SyncFailure("SCAN_FAILED", "a cookie query failed")
                }
            for (line in lines) {
                val parsed = SetCookieLine.parse(line) ?: continue
                if (parsed.partitioned) continue
                cookies[Triple(parsed.domain, parsed.path, parsed.name)] = parsed
            }
        }
        return CookieSnapshot(
            cookies = JsonArray(cookies.values.map { SyncMaps.toJson(it.wire()) }),
            coverage = buildJsonObject { put("urls", JsonArray(urls.map(::JsonPrimitive))) },
        )
    }

    override fun apply(
        op: JsonObject,
        entries: List<EntryLocation>,
    ): JsonObject {
        val id = op["id"] ?: JsonPrimitive(0)
        val cookie = op.obj("cookie") ?: throw SyncFailure("INVALID_MESSAGE", "op needs a cookie")
        val domain = cookie.string("domain") ?: throw SyncFailure("INVALID_MESSAGE", "op needs a domain")
        val path = cookie.string("path") ?: "/"
        val name = cookie.string("name") ?: throw SyncFailure("INVALID_MESSAGE", "op needs a name")
        var ok =
            runCatching {
                val header =
                    if (op.string("op") == "delete") {
                        SetCookieLine.forDelete(domain, path, name)
                    } else {
                        @Suppress("UNCHECKED_CAST")
                        SetCookieLine.forWrite(SyncMaps.fromJson(cookie) as Map<String, Any?>)
                    }
                engine.set(SetCookieLine.url(domain, path), header)
                engine.flush()
            }.isSuccess
        val (readback, complete) = readback(domain, path, name, entries)
        if (!complete) ok = false
        return buildJsonObject {
            put("id", id)
            put("ok", ok)
            put("readback", JsonArray(readback.map { SyncMaps.toJson(it.wire()) }))
        }
    }

    /**
     * Every engine cookie named [name] whose domain without its dot equals the
     * op's host. WebView answers per URL, so this queries the op's path, `/` and
     * every known path for the host; a cookie under a path none of them reaches
     * cannot be seen. A failed query leaves the result incomplete (`ok:false`)
     * but keeps whatever the other queries returned.
     */
    fun readback(
        domain: String,
        path: String,
        name: String,
        entries: List<EntryLocation>,
    ): Pair<List<SetCookieLine.Parsed>, Boolean> {
        val host = domain.removePrefix(".")
        val paths = (listOf(path, "/") + entries.filter { it.domain.removePrefix(".") == host }.map { it.path }).distinct()
        val found = linkedMapOf<Triple<String, String, String>, SetCookieLine.Parsed>()
        var complete = true
        for (candidate in paths) {
            val lines =
                try {
                    engine.info(SetCookieLine.url(host, candidate))
                } catch (error: Exception) {
                    complete = false
                    continue
                }
            lines
                .mapNotNull(SetCookieLine::parse)
                .filter { it.name == name && it.host == host && !it.partitioned }
                .forEach { found[Triple(it.domain, it.path, it.name)] = it }
        }
        return found.values.toList() to complete
    }
}

/** Builds the exact-URL coverage list for an Android scan. */
object CoverageUrls {
    private const val MAX_HISTORY_HOSTS = 500
    private const val MAX_URLS = 20_000

    fun build(
        entries: List<EntryLocation>,
        hosts: Set<String>?,
        historyHosts: List<String>,
        recentUrls: List<String>,
    ): List<String> {
        val urls = LinkedHashSet<String>()
        for (entry in entries) {
            val host = entry.domain.removePrefix(".")
            if (hosts != null && host !in hosts) continue
            if (eligible(host)) urls.add(SetCookieLine.url(host, entry.path))
        }
        if (hosts != null) hosts.filter(::eligible).forEach { urls.add(SetCookieLine.url(it)) }
        historyHosts
            .asSequence()
            .filter(::eligible)
            .distinct()
            .take(MAX_HISTORY_HOSTS)
            .forEach { urls.add(SetCookieLine.url(it)) }
        for (page in recentUrls) {
            val parts = pageParts(page) ?: continue
            if (!eligible(parts.first) || (hosts != null && parts.first !in hosts)) continue
            urls.add(SetCookieLine.url(parts.first))
            urls.add(SetCookieLine.url(parts.first, parts.second))
        }
        return urls.take(MAX_URLS)
    }

    /** Host and path of an http(s) page URL. */
    fun pageParts(url: String): Pair<String, String>? {
        val uri = runCatching { java.net.URI(url) }.getOrNull() ?: return null
        if (uri.scheme?.lowercase() !in setOf("http", "https")) return null
        val host =
            uri.host
                ?.lowercase()
                ?.removePrefix("[")
                ?.removeSuffix("]") ?: return null
        val path = uri.rawPath?.takeIf { it.startsWith("/") } ?: "/"
        return host to path
    }

    /** Loopback hosts never sync; IP literals and names otherwise qualify. */
    fun eligible(host: String): Boolean {
        val lower = host.lowercase()
        if (lower.isEmpty() || lower == "localhost" || lower.endsWith(".localhost") || lower == "::1") return false
        return !(lower.startsWith("127.") && lower.all { it.isDigit() || it == '.' })
    }
}
