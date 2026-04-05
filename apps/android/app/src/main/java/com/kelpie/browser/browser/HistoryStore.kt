package com.kelpie.browser.browser

import android.content.Context
import android.content.SharedPreferences
import com.kelpie.browser.nativecore.NativeCore
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
    private const val PREFS_NAME = "kelpie_history"
    private const val DATA_KEY = "data"

    private lateinit var prefs: SharedPreferences
    private val nativeHandle = NativeCore.historyStoreCreate()
    private val lock = Any()
    private val _entries = MutableStateFlow<List<HistoryEntry>>(emptyList())
    val entries: StateFlow<List<HistoryEntry>> = _entries.asStateFlow()

    fun init(context: Context) {
        synchronized(lock) {
            prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            NativeCore.historyStoreLoadJson(nativeHandle, prefs.getString(DATA_KEY, null))
            refreshFromNative(save = false)
        }
    }

    fun record(url: String, title: String) {
        synchronized(lock) {
            NativeCore.historyStoreRecord(nativeHandle, url, title)
            refreshFromNative(save = true)
        }
    }

    fun clear() {
        synchronized(lock) {
            NativeCore.historyStoreClear(nativeHandle)
            refreshFromNative(save = true)
        }
    }

    fun updateLatestTitle(url: String, title: String) {
        synchronized(lock) {
            NativeCore.historyStoreUpdateLatestTitle(nativeHandle, url, title)
            refreshFromNative(save = true)
        }
    }

    fun toJSON(): List<Map<String, Any>> = _entries.value.asReversed().map { e ->
        mapOf("id" to e.id, "url" to e.url, "title" to e.title, "timestamp" to e.timestamp)
    }

    private fun refreshFromNative(save: Boolean) {
        val newestFirst = parseHistoryEntries(NativeCore.historyStoreToJson(nativeHandle))
        _entries.value = newestFirst.asReversed()
        if (save) {
            saveHistoryJson(_entries.value)
        }
    }

    private fun saveHistoryJson(entries: List<HistoryEntry>) {
        val arr = JSONArray()
        entries.forEach { e ->
            arr.put(JSONObject().apply {
                put("id", e.id); put("url", e.url); put("title", e.title); put("timestamp", e.timestamp)
            })
        }
        prefs.edit().putString(DATA_KEY, arr.toString()).apply()
    }

    private fun parseHistoryEntries(json: String?): List<HistoryEntry> {
        if (json.isNullOrBlank()) {
            return emptyList()
        }

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
        return list
    }
}
