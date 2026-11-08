package com.kelpie.browser

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.enableEdgeToEdge

/** Optional standalone-window host; other apps may embed KelpieBrowserSession.view(). */
open class KelpieBrowserActivity : ComponentActivity() {
    private lateinit var browser: KelpieBrowserSession

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        browser = KelpieBrowserSession(this)
        setContentView(browser.view())
    }

    override fun onTrimMemory(level: Int) {
        super.onTrimMemory(level)
        if (::browser.isInitialized) browser.trimMemory()
    }
}
