package com.kelpie.browser

import android.content.Context
import android.webkit.WebView
import com.kelpie.browser.ai.AIState
import com.kelpie.browser.browser.NetworkTrafficStore
import com.kelpie.browser.ui.TabletViewportPresetStore

object KelpieEnvironment {
    lateinit var app: Context
        private set

    fun standalone(context: Context): Boolean = context.packageName in setOf("com.kelpie.browser", "com.kelpie.browser.nessieverify")

    fun context(context: Context): Context = if (standalone(context)) context else KelpieStorageContext(context)

    fun initialize(context: Context) {
        if (::app.isInitialized) return
        app = if (standalone(context)) context.applicationContext else KelpieStorageContext(context.applicationContext)
        com.kelpie.browser.browser.PartitionRegistry
            .initialize(app)
        // Embedded browsing leaves the containing app's process-wide debug policy intact.
        if (standalone(context)) WebView.setWebContentsDebuggingEnabled(true)
        NetworkTrafficStore.init(app)
        TabletViewportPresetStore.init(app)
        AIState.initialize(app)
    }
}
