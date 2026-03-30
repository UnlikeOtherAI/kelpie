package com.mollotov.browser

import android.app.Application
import android.webkit.WebView

class MollotovApp : Application() {
    override fun onCreate() {
        super.onCreate()
        // Enable Chrome DevTools Protocol for WebView
        WebView.setWebContentsDebuggingEnabled(true)
    }
}
