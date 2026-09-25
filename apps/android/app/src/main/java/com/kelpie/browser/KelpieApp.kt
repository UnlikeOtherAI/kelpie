package com.kelpie.browser

import android.app.Application
import android.webkit.WebView
import com.kelpie.browser.ai.AIState
import com.kelpie.browser.browser.NetworkTrafficStore
import com.kelpie.browser.ui.TabletViewportPresetStore

class KelpieApp : Application() {
    companion object {
        lateinit var app: KelpieApp
            private set
    }

    override fun onCreate() {
        super.onCreate()
        app = this
        if (getProcessName().endsWith(":auth")) {
            WebView.setDataDirectorySuffix("account-login")
            WebView.setWebContentsDebuggingEnabled(false)
            return
        }
        // Enable Chrome DevTools Protocol for WebView
        WebView.setWebContentsDebuggingEnabled(true)
        NetworkTrafficStore.init(this)
        TabletViewportPresetStore.init(this)
        AIState.initialize(this)
    }
}
