package com.kelpie.browser

import android.content.Context
import android.webkit.WebView
import com.kelpie.browser.ai.AIState
import com.kelpie.browser.browser.NetworkTrafficStore
import com.kelpie.browser.ui.TabletViewportPresetStore

object KelpieEnvironment {
    lateinit var app: Context
        private set

    fun initialize(context: Context) {
        if (::app.isInitialized) return
        app = context.applicationContext
        com.kelpie.browser.browser.PartitionRegistry
            .initialize(app)
        // Enable Chrome DevTools Protocol for WebView
        WebView.setWebContentsDebuggingEnabled(true)
        NetworkTrafficStore.init(app)
        TabletViewportPresetStore.init(app)
        AIState.initialize(app)
    }
}
