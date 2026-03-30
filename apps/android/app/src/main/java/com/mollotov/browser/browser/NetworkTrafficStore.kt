package com.mollotov.browser.browser

import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
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
    val startTime: String = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss'Z'", Locale.US).format(Date()),
    val duration: Int = 0,
    val size: Int = 0,
) {
    val category: String
        get() = when {
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

    fun append(entry: TrafficEntry) {
        val updated = _entries.value + entry
        _entries.value = if (updated.size > 2000) updated.drop(updated.size - 2000) else updated
    }

    fun clear() {
        _entries.value = emptyList()
        _selectedIndex.value = null
    }

    fun select(index: Int) {
        _selectedIndex.value = index
    }

    fun entryToMap(entry: TrafficEntry): Map<String, Any?> = mapOf(
        "id" to entry.id,
        "method" to entry.method,
        "url" to entry.url,
        "statusCode" to entry.statusCode,
        "contentType" to entry.contentType,
        "category" to entry.category,
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
    ): List<Map<String, Any?>> {
        var filtered = _entries.value
        if (method != null) filtered = filtered.filter { it.method.equals(method, ignoreCase = true) }
        if (category != null) filtered = filtered.filter { it.category.equals(category, ignoreCase = true) }
        if (urlPattern != null) filtered = filtered.filter { it.url.contains(urlPattern) }
        if (statusRange != null) {
            val parts = statusRange.split("-").mapNotNull { it.toIntOrNull() }
            if (parts.size == 2) filtered = filtered.filter { it.statusCode in parts[0]..parts[1] }
            else if (parts.size == 1) filtered = filtered.filter { it.statusCode == parts[0] }
        }
        return filtered.mapIndexed { idx, e ->
            mapOf<String, Any?>(
                "index" to idx, "method" to e.method, "url" to e.url,
                "statusCode" to e.statusCode, "contentType" to e.contentType,
                "category" to e.category, "duration" to e.duration, "size" to e.size,
            )
        }
    }
}
