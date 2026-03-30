package com.mollotov.browser.browser

import android.content.Context
import android.content.SharedPreferences
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import org.json.JSONArray
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.UUID

data class HistoryEntry(
    val id: String = UUID.randomUUID().toString(),
    val url: String,
    val title: String,
    val timestamp: String = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss'Z'", Locale.US).format(Date()),
)

object HistoryStore {
    private lateinit var prefs: SharedPreferences
    private val _entries = MutableStateFlow<List<HistoryEntry>>(emptyList())
    val entries: StateFlow<List<HistoryEntry>> = _entries.asStateFlow()
    private const val MAX_ENTRIES = 500

    fun init(context: Context) {
        prefs = context.getSharedPreferences("mollotov_history", Context.MODE_PRIVATE)
        load()
    }

    fun record(url: String, title: String) {
        if (_entries.value.lastOrNull()?.url == url) return
        val updated = _entries.value + HistoryEntry(url = url, title = title)
        _entries.value = if (updated.size > MAX_ENTRIES) updated.drop(updated.size - MAX_ENTRIES) else updated
        save()
    }

    fun clear() {
        _entries.value = emptyList()
        save()
    }

    fun toJSON(): List<Map<String, Any>> = _entries.value.reversed().map { e ->
        mapOf("id" to e.id, "url" to e.url, "title" to e.title, "timestamp" to e.timestamp)
    }

    private fun save() {
        val arr = JSONArray()
        _entries.value.forEach { e ->
            arr.put(JSONObject().apply {
                put("id", e.id); put("url", e.url); put("title", e.title); put("timestamp", e.timestamp)
            })
        }
        prefs.edit().putString("data", arr.toString()).apply()
    }

    private fun load() {
        val json = prefs.getString("data", null) ?: return
        val arr = JSONArray(json)
        val list = mutableListOf<HistoryEntry>()
        for (i in 0 until arr.length()) {
            val obj = arr.getJSONObject(i)
            list.add(HistoryEntry(
                id = obj.getString("id"),
                url = obj.getString("url"),
                title = obj.getString("title"),
                timestamp = obj.optString("timestamp", ""),
            ))
        }
        _entries.value = list
    }
}
