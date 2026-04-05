package com.kelpie.browser.browser

import android.content.Context
import android.content.SharedPreferences
import com.kelpie.browser.nativecore.NativeCore
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import org.json.JSONArray
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
    private const val PREFS_NAME = "kelpie_bookmarks"
    private const val DATA_KEY = "data"

    private lateinit var prefs: SharedPreferences
    private val nativeHandle = NativeCore.bookmarkStoreCreate()
    private val lock = Any()
    private val _bookmarks = MutableStateFlow<List<Bookmark>>(emptyList())
    val bookmarks: StateFlow<List<Bookmark>> = _bookmarks.asStateFlow()

    fun init(context: Context) {
        synchronized(lock) {
            prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            NativeCore.bookmarkStoreLoadJson(nativeHandle, prefs.getString(DATA_KEY, null))
            _bookmarks.value = parseBookmarks(NativeCore.bookmarkStoreToJson(nativeHandle))
        }
    }

    fun add(title: String, url: String) {
        synchronized(lock) {
            NativeCore.bookmarkStoreAdd(nativeHandle, title, url)
            refreshFromNative(save = true)
        }
    }

    fun remove(id: String) {
        synchronized(lock) {
            NativeCore.bookmarkStoreRemove(nativeHandle, id)
            refreshFromNative(save = true)
        }
    }

    fun clear() {
        synchronized(lock) {
            NativeCore.bookmarkStoreRemoveAll(nativeHandle)
            refreshFromNative(save = true)
        }
    }

    fun toJSON(): List<Map<String, Any>> = _bookmarks.value.map { b ->
        mapOf("id" to b.id, "title" to b.title, "url" to b.url, "createdAt" to b.createdAt)
    }

    private fun refreshFromNative(save: Boolean) {
        val json = NativeCore.bookmarkStoreToJson(nativeHandle)
        _bookmarks.value = parseBookmarks(json)
        if (save) {
            prefs.edit().putString(DATA_KEY, json ?: "[]").apply()
        }
    }

    private fun parseBookmarks(json: String?): List<Bookmark> {
        if (json.isNullOrBlank()) {
            return emptyList()
        }

        val arr = JSONArray(json)
        val list = mutableListOf<Bookmark>()
        for (i in 0 until arr.length()) {
            val obj = arr.getJSONObject(i)
            list.add(Bookmark(
                id = obj.getString("id"),
                title = obj.getString("title"),
                url = obj.getString("url"),
                createdAt = obj.optString("created_at", obj.optString("createdAt", "")),
            ))
        }
        return list
    }
}
