package com.kelpie.browser.browser

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject

/** Versioned tab identities; older builds receive only the ordinary-tab URL snapshot. */
object SessionStore {
    private const val PREFS_NAME = "kelpie_prefs"
    private const val KEY_TABS = "session_tabs_v2"
    private const val KEY_URLS = "session_tab_urls"
    private const val KEY_ACTIVE = "session_active_index"

    data class TabRecord(
        val url: String,
        val partition: String?,
        val name: String?,
    )

    data class Snapshot(
        val tabs: List<TabRecord>,
        val activeIndex: Int,
    )

    fun save(
        context: Context,
        tabs: List<BrowserTab>,
        activeId: String?,
    ) {
        val valid = tabs.filter { it.currentUrl.isNotEmpty() && !it.isStartPage }
        val records = JSONArray()
        valid.forEach { tab ->
            records.put(
                JSONObject().apply {
                    put("url", tab.currentUrl)
                    put("partition", tab.partition)
                    put("name", tab.name)
                },
            )
        }
        val snapshot =
            JSONObject().apply {
                put("version", 2)
                put("tabs", records)
                put("activeIndex", valid.indexOfFirst { it.id == activeId }.coerceAtLeast(0))
            }
        context
            .getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit()
            .putString(KEY_TABS, snapshot.toString())
            .putString(KEY_URLS, valid.filter { it.partition == null }.joinToString("\n") { it.currentUrl })
            .putInt(KEY_ACTIVE, 0)
            .apply()
    }

    fun load(context: Context): Snapshot? {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val versioned = prefs.getString(KEY_TABS, null)
        if (versioned != null) return decode(versioned)
        val raw = prefs.getString(KEY_URLS, null) ?: return null
        return Snapshot(
            raw.split("\n").filter { it.isNotEmpty() }.map { TabRecord(it, null, null) },
            prefs.getInt(KEY_ACTIVE, 0).coerceAtLeast(0),
        )
    }

    internal fun decode(raw: String): Snapshot? =
        runCatching {
            val obj = JSONObject(raw)
            require(obj.getInt("version") == 2)
            val records = obj.getJSONArray("tabs")
            val tabs =
                (0 until records.length()).map { index ->
                    val record = records.getJSONObject(index)
                    val partition = if (record.has("partition")) record.get("partition") as String else null
                    partition?.let(PartitionRegistry::validateId)
                    TabRecord(record.getString("url"), partition, record.optString("name").takeIf { it.isNotEmpty() })
                }
            Snapshot(tabs, obj.getInt("activeIndex").coerceAtLeast(0))
        }.getOrNull()

    fun clear(context: Context) {
        context
            .getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit()
            .remove(KEY_TABS)
            .remove(KEY_URLS)
            .remove(KEY_ACTIVE)
            .apply()
    }
}
