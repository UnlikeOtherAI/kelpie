package com.kelpie.browser.browser

import android.content.Context
import android.content.SharedPreferences
import com.kelpie.browser.KelpieEnvironment
import com.kelpie.browser.nativecore.NativeCore
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone
import java.util.UUID

data class TrafficEntry(
    val id: String = UUID.randomUUID().toString(),
    val method: String,
    val url: String,
    val statusCode: Int,
    val contentType: String,
    val requestHeaders: Map<String, String> = emptyMap(),
    val responseHeaders: Map<String, String> = emptyMap(),
    val requestBody: String? = null,
    val responseBody: String? = null,
    val startTime: String = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss'Z'", Locale.US).apply { timeZone = TimeZone.getTimeZone("UTC") }.format(Date()),
    val duration: Int = 0,
    val size: Int = 0,
    val initiator: String = "browser", // "browser" or "js"
) {
    val category: String
        get() =
            when {
                contentType.contains("json") -> "JSON"
                contentType.contains("html") -> "HTML"
                contentType.contains("css") -> "CSS"
                contentType.contains("javascript") || contentType.contains("ecmascript") -> "JS"
                contentType.contains("image") -> "Image"
                contentType.contains("font") -> "Font"
                contentType.contains("xml") -> "XML"
                else -> "Other"
            }
}

object NetworkTrafficStore {
    private const val PREFS_NAME = "kelpie_network_traffic"
    private const val DATA_KEY = "data"

    private lateinit var prefs: SharedPreferences
    private lateinit var persistence: NetworkTrafficPersistence
    private val nativeHandle = NativeCore.networkTrafficStoreCreate()
    private val lock = Any()
    private val _entries = MutableStateFlow<List<TrafficEntry>>(emptyList())
    val entries: StateFlow<List<TrafficEntry>> = _entries.asStateFlow()

    private val _selectedIndex = MutableStateFlow<Int?>(null)
    val selectedIndex: StateFlow<Int?> = _selectedIndex.asStateFlow()

    val selectedEntry: TrafficEntry?
        get() {
            val idx = _selectedIndex.value ?: return null
            val list = _entries.value
            return if (idx in list.indices) list[idx] else null
        }

    internal fun init(context: Context) {
        synchronized(lock) {
            if (::persistence.isInitialized) return
            prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            persistence =
                NetworkTrafficPersistence(
                    File(context.noBackupFilesDir, "network/traffic.json"),
                    encode = { entries -> "[" + entries.joinToString(",", transform = ::trafficEntryToJson) + "]" },
                    migrated = { check(prefs.edit().remove(DATA_KEY).commit()) { "Legacy migration could not be saved" } },
                )
            val saved = persistence.load()
            val json =
                if (saved != null && runCatching { parseTrafficEntries(saved) }.isSuccess) {
                    saved
                } else {
                    if (saved != null) persistence.preserveUnreadableFile()
                    prefs.getString(DATA_KEY, null)?.takeIf { runCatching { parseTrafficEntries(it) }.isSuccess }
                }
            NativeCore.networkTrafficStoreLoadJson(nativeHandle, json)
            _entries.value = parseTrafficEntries(NativeCore.networkTrafficStoreToJson(nativeHandle))
            synchronizeSelection()
            if (prefs.contains(DATA_KEY) && json != null) persistence.save(_entries.value)
        }
    }

    fun append(entry: TrafficEntry) {
        synchronized(lock) {
            ensureInitialized()
            val accepted =
                entry.copy(
                    id = entry.id.ifEmpty { UUID.randomUUID().toString() },
                    startTime = entry.startTime.ifEmpty { TrafficEntry(method = "GET", url = "", statusCode = 0, contentType = "").startTime },
                )
            if (!NativeCore.networkTrafficStoreAppendJson(nativeHandle, trafficEntryToJson(accepted))) return
            val normalized =
                accepted.copy(
                    method = entry.method.map { if (it in 'a'..'z') it.uppercaseChar() else it }.joinToString(""),
                    requestHeaders = entry.requestHeaders.toMap(),
                    responseHeaders = entry.responseHeaders.toMap(),
                    requestBody = entry.requestBody?.takeIf { it.isNotEmpty() },
                    responseBody = entry.responseBody?.takeIf { it.isNotEmpty() },
                    duration = entry.duration.coerceAtLeast(0),
                    size = entry.size.coerceAtLeast(0),
                    initiator = "browser",
                )
            _entries.value = (_entries.value + normalized).takeLast(NativeCore.networkTrafficStoreCount(nativeHandle))
            synchronizeSelection()
            persistence.save(_entries.value)
        }
    }

    fun appendDocumentNavigation(
        url: String,
        statusCode: Int,
        contentType: String,
        responseHeaders: Map<String, String> = emptyMap(),
        size: Int = 0,
    ) {
        append(
            TrafficEntry(
                method = "GET",
                url = url,
                statusCode = statusCode,
                contentType = contentType,
                responseHeaders = responseHeaders,
                size = size,
            ),
        )
    }

    fun clear() {
        synchronized(lock) {
            ensureInitialized()
            NativeCore.networkTrafficStoreClear(nativeHandle)
            _entries.value = emptyList()
            synchronizeSelection()
            persistence.save(emptyList())
            persistence.flush()
        }
    }

    fun select(index: Int) {
        synchronized(lock) {
            ensureInitialized()
            NativeCore.networkTrafficStoreSelect(nativeHandle, index)
            synchronizeSelection()
        }
    }

    fun entryToMap(entry: TrafficEntry): Map<String, Any?> =
        mapOf(
            "id" to entry.id,
            "method" to entry.method,
            "url" to entry.url,
            "statusCode" to entry.statusCode,
            "contentType" to entry.contentType,
            "category" to entry.category,
            "initiator" to entry.initiator,
            "requestHeaders" to entry.requestHeaders,
            "responseHeaders" to entry.responseHeaders,
            "requestBody" to (entry.requestBody ?: ""),
            "responseBody" to (entry.responseBody ?: ""),
            "startTime" to entry.startTime,
            "duration" to entry.duration,
            "size" to entry.size,
        )

    fun toSummaryList(
        method: String? = null,
        category: String? = null,
        statusRange: String? = null,
        urlPattern: String? = null,
    ): List<Map<String, Any?>> =
        synchronized(lock) {
            ensureInitialized()
            parseSummaryList(
                NativeCore.networkTrafficStoreToSummaryJson(
                    handle = nativeHandle,
                    method = method,
                    category = category,
                    statusRange = statusRange,
                    urlPattern = urlPattern,
                ),
            )
        }

    private fun ensureInitialized() {
        if (!::prefs.isInitialized) {
            init(KelpieEnvironment.app)
        }
    }

    fun flush() {
        synchronized(lock) { if (::persistence.isInitialized) persistence.flush() }
    }

    private fun synchronizeSelection() {
        _selectedIndex.value = NativeCore.networkTrafficStoreSelectedIndex(nativeHandle).takeIf { it >= 0 }
    }

    private fun parseTrafficEntries(json: String?): List<TrafficEntry> {
        if (json.isNullOrBlank()) {
            return emptyList()
        }

        val arr = JSONArray(json)
        val list = mutableListOf<TrafficEntry>()
        for (i in 0 until arr.length()) {
            list += arr.getJSONObject(i).toTrafficEntry()
        }
        return list
    }

    private fun parseSummaryList(json: String?): List<Map<String, Any?>> {
        if (json.isNullOrBlank()) {
            return emptyList()
        }

        val arr = JSONArray(json)
        val list = ArrayList<Map<String, Any?>>(arr.length())
        for (i in 0 until arr.length()) {
            val obj = arr.getJSONObject(i)
            list +=
                mapOf(
                    "index" to obj.optInt("index"),
                    "method" to obj.optString("method"),
                    "url" to obj.optString("url"),
                    "statusCode" to optInt(obj, "status_code", "statusCode"),
                    "contentType" to optString(obj, "content_type", "contentType"),
                    "category" to obj.optString("category"),
                    "duration" to obj.optInt("duration"),
                    "size" to obj.optInt("size"),
                )
        }
        return list
    }

    private fun JSONObject.toTrafficEntry(): TrafficEntry =
        TrafficEntry(
            id = getString("id"),
            method = optString("method", "GET"),
            url = optString("url", ""),
            statusCode = optInt(this, "status_code", "statusCode"),
            contentType = optString(this, "content_type", optString("contentType", "")),
            requestHeaders = optStringMap(this, "request_headers", "requestHeaders"),
            responseHeaders = optStringMap(this, "response_headers", "responseHeaders"),
            requestBody = optNullableString(this, "request_body", "requestBody"),
            responseBody = optNullableString(this, "response_body", "responseBody"),
            startTime = optString(this, "start_time", optString("startTime", "")),
            duration = optInt("duration"),
            size = optInt("size"),
            initiator = optString("initiator", "browser"),
        )

    private fun trafficEntryToJson(entry: TrafficEntry): String =
        JSONObject()
            .apply {
                put("id", entry.id)
                put("method", entry.method)
                put("url", entry.url)
                put("statusCode", entry.statusCode)
                put("contentType", entry.contentType)
                put("initiator", entry.initiator)
                put("requestHeaders", JSONObject(entry.requestHeaders))
                put("responseHeaders", JSONObject(entry.responseHeaders))
                put("requestBody", entry.requestBody ?: "")
                put("responseBody", entry.responseBody ?: "")
                put("startTime", entry.startTime)
                put("duration", entry.duration)
                put("size", entry.size)
            }.toString()

    private fun optInt(
        obj: JSONObject,
        snakeCase: String,
        camelCase: String,
    ): Int = if (obj.has(snakeCase)) obj.optInt(snakeCase) else obj.optInt(camelCase)

    private fun optString(
        obj: JSONObject,
        key: String,
        fallback: String,
    ): String = if (obj.has(key)) obj.optString(key, fallback) else fallback

    private fun optStringMap(
        obj: JSONObject,
        snakeCase: String,
        camelCase: String,
    ): Map<String, String> {
        val source =
            when {
                obj.has(snakeCase) -> obj.optJSONObject(snakeCase)
                else -> obj.optJSONObject(camelCase)
            } ?: return emptyMap()

        val values = LinkedHashMap<String, String>(source.length())
        for (key in source.keys()) {
            values[key] = source.optString(key, "")
        }
        return values
    }

    private fun optNullableString(
        obj: JSONObject,
        snakeCase: String,
        camelCase: String,
    ): String? {
        val key =
            when {
                obj.has(snakeCase) -> snakeCase
                obj.has(camelCase) -> camelCase
                else -> return null
            }
        return obj.optString(key).takeIf { it.isNotEmpty() }
    }
}
