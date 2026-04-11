package com.kelpie.browser.browser

import android.content.Context

/** Persists and restores the set of open tab URLs across app launches. */
object SessionStore {
    private const val PREFS_NAME = "kelpie_prefs"
    private const val KEY_URLS = "session_tab_urls"
    private const val KEY_ACTIVE = "session_active_index"

    fun save(
        context: Context,
        tabs: List<BrowserTab>,
        activeId: String?,
    ) {
        val valid = tabs.filter { it.currentUrl.isNotEmpty() && !it.isStartPage }
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        if (valid.isEmpty()) {
            prefs
                .edit()
                .remove(KEY_URLS)
                .remove(KEY_ACTIVE)
                .apply()
            return
        }
        val urls = valid.map { it.currentUrl }
        val activeIndex = valid.indexOfFirst { it.id == activeId }.coerceAtLeast(0)
        prefs
            .edit()
            .putString(KEY_URLS, urls.joinToString("\n"))
            .putInt(KEY_ACTIVE, activeIndex)
            .apply()
    }

    fun load(context: Context): Pair<List<String>, Int>? {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val raw = prefs.getString(KEY_URLS, null) ?: return null
        val urls = raw.split("\n").filter { it.isNotEmpty() }
        if (urls.isEmpty()) return null
        val active = prefs.getInt(KEY_ACTIVE, 0)
        return urls to active
    }

    fun clear(context: Context) {
        context
            .getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit()
            .remove(KEY_URLS)
            .remove(KEY_ACTIVE)
            .apply()
    }
}
