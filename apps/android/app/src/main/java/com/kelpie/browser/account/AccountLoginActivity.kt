package com.kelpie.browser.account

import android.app.Activity
import android.content.Intent
import android.os.Bundle
import android.webkit.CookieManager
import android.webkit.WebResourceRequest
import android.webkit.WebStorage
import android.webkit.WebView
import android.webkit.WebViewClient
import android.widget.LinearLayout
import android.widget.TextView
import android.view.WindowManager

/** Hosted login in a dedicated process/profile, never in the browser tab registry. */
class AccountLoginActivity : Activity() {
    private var webView: WebView? = null
    private var registered = false
    private val nonce: String? get() = intent.getStringExtra("nonce")
    private val cancelled = object : android.content.BroadcastReceiver() {
        override fun onReceive(context: android.content.Context, intent: Intent) {
            if (intent.getStringExtra("nonce") == nonce) finish()
        }
    }
    companion object { const val CANCEL = "com.kelpie.browser.CANCEL_ACCOUNT_LOGIN" }

    @android.annotation.SuppressLint("SetJavaScriptEnabled")
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setResult(RESULT_CANCELED, Intent().putExtra("nonce", nonce))
        androidx.core.content.ContextCompat.registerReceiver(this, cancelled, android.content.IntentFilter(CANCEL), androidx.core.content.ContextCompat.RECEIVER_NOT_EXPORTED)
        registered = true
        window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
        val url = intent.getStringExtra("url") ?: return finish()
        val initial = android.net.Uri.parse(url)
        if (initial.scheme != "https" || initial.host != "authentication.unlikeotherai.com" || initial.path != "/oauth/authorize") return finish()
        val layout = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL }
        val location = TextView(this).apply { setPadding(20, 16, 20, 16); text = "authentication.unlikeotherai.com" }
        layout.addView(location)
        val view = WebView(this)
        webView = view
        view.settings.javaScriptEnabled = true
        view.settings.domStorageEnabled = true
        view.settings.allowFileAccess = false
        view.settings.allowContentAccess = false
        view.settings.saveFormData = false
        view.settings.setSupportMultipleWindows(false)
        view.webViewClient = object : WebViewClient() {
            override fun shouldOverrideUrlLoading(view: WebView, request: WebResourceRequest): Boolean {
                val next = request.url
                if (next.scheme == "com.unlikeotherai.kelpie" && next.host == "oauth" && next.path == "/callback") {
                    setResult(RESULT_OK, Intent().setData(next).putExtra("nonce", nonce))
                    finish()
                    return true
                }
                return next.scheme != "https"
            }
            override fun onPageStarted(view: WebView, url: String, favicon: android.graphics.Bitmap?) {
                val current = android.net.Uri.parse(url)
                location.text = "${current.scheme}://${current.host.orEmpty()}"
            }
        }
        layout.addView(view, LinearLayout.LayoutParams(-1, 0, 1f))
        setContentView(layout)
        CookieManager.getInstance().removeAllCookies {
            if (!isFinishing) { view.clearCache(true); WebStorage.getInstance().deleteAllData(); view.loadUrl(url) }
        }
    }

    override fun onDestroy() {
        if (registered) unregisterReceiver(cancelled)
        webView?.apply { stopLoading(); clearHistory(); clearCache(true); destroy() }
        webView = null
        CookieManager.getInstance().removeAllCookies(null)
        WebStorage.getInstance().deleteAllData()
        super.onDestroy()
    }
}
