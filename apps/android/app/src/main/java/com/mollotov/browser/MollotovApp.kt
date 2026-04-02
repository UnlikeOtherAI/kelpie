package com.mollotov.browser

import android.app.Application
import android.webkit.WebView
import com.mollotov.browser.ai.AIState
import com.mollotov.browser.browser.NetworkTrafficStore
import com.mollotov.browser.ui.TabletViewportPresetStore

class MollotovApp : Application() {
    companion object {
        lateinit var app: MollotovApp
            private set
    }

    override fun onCreate() {
        super.onCreate()
        app = this
        // Enable Chrome DevTools Protocol for WebView
        WebView.setWebContentsDebuggingEnabled(true)
        NetworkTrafficStore.init(this)
        TabletViewportPresetStore.init(this)
        AIState.initialize(this)
    }
}
