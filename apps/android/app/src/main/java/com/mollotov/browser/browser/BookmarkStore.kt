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

data class Bookmark(
    val id: String = UUID.randomUUID().toString(),
    val title: String,
    val url: String,
    val createdAt: String = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss'Z'", Locale.US).format(Date()),
)

object BookmarkStore {
    private lateinit var prefs: SharedPreferences
    private val _bookmarks = MutableStateFlow<List<Bookmark>>(emptyList())
    val bookmarks: StateFlow<List<Bookmark>> = _bookmarks.asStateFlow()

    fun init(context: Context) {
        prefs = context.getSharedPreferences("mollotov_bookmarks", Context.MODE_PRIVATE)
        load()
    }

    fun add(title: String, url: String) {
        _bookmarks.value = _bookmarks.value + Bookmark(title = title, url = url)
        save()
    }

    fun remove(id: String) {
        _bookmarks.value = _bookmarks.value.filter { it.id != id }
        save()
    }

    fun clear() {
        _bookmarks.value = emptyList()
        save()
    }

    fun toJSON(): List<Map<String, Any>> = _bookmarks.value.map { b ->
        mapOf("id" to b.id, "title" to b.title, "url" to b.url, "createdAt" to b.createdAt)
    }

    private fun save() {
        val arr = JSONArray()
        _bookmarks.value.forEach { b ->
            arr.put(JSONObject().apply {
                put("id", b.id); put("title", b.title); put("url", b.url); put("createdAt", b.createdAt)
            })
        }
        prefs.edit().putString("data", arr.toString()).apply()
    }

    private fun load() {
        val json = prefs.getString("data", null) ?: return
        val arr = JSONArray(json)
        val list = mutableListOf<Bookmark>()
        for (i in 0 until arr.length()) {
            val obj = arr.getJSONObject(i)
            list.add(Bookmark(
                id = obj.getString("id"),
                title = obj.getString("title"),
                url = obj.getString("url"),
                createdAt = obj.optString("createdAt", ""),
            ))
        }
        _bookmarks.value = list
    }
}
