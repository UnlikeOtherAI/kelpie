package com.kelpie.browser.browser

import android.content.Context
import android.content.SharedPreferences

const val DEFAULT_HOME_URL = "https://unlikeotherai.github.io/kelpie"

object HomeStore {
    private lateinit var prefs: SharedPreferences

    val url: String
        get() =
            if (::prefs.isInitialized) {
                prefs.getString("homeURL", DEFAULT_HOME_URL) ?: DEFAULT_HOME_URL
            } else {
                DEFAULT_HOME_URL
            }

    fun init(context: Context) {
        prefs = context.getSharedPreferences("kelpie_prefs", Context.MODE_PRIVATE)
    }

    fun setUrl(url: String) {
        prefs.edit().putString("homeURL", url).apply()
    }
}
