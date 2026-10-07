package com.kelpie.browser.account

import android.app.Activity
import android.content.Intent
import android.os.Bundle
import android.view.WindowManager
import android.webkit.CookieManager
import android.webkit.WebResourceRequest
import android.webkit.WebView
import android.webkit.WebViewClient
import android.widget.LinearLayout
import android.widget.TextView
import com.kelpie.browser.browser.BROWSER_USER_AGENT

/**
 * Hosted UOA login in the main process and the default WebView profile, so the Google (and UOA)
 * cookies and storage it creates are shared with every browser tab by design. It is not a tab:
 * it is never registered with the tab store, history, session persistence or automation, and it
 * exposes no JavaScript bridge.
 */
class AccountLoginActivity : Activity() {
    private var webView: WebView? = null
    private var registered = false
    private val nonce: String? get() = intent.getStringExtra("nonce")
    private val cancelled =
        object : android.content.BroadcastReceiver() {
            override fun onReceive(
                context: android.content.Context,
                intent: Intent,
            ) {
                if (intent.getStringExtra("nonce") == nonce) finish()
            }
        }

    companion object {
        const val CANCEL = "com.kelpie.browser.CANCEL_ACCOUNT_LOGIN"
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setResult(RESULT_CANCELED, Intent().putExtra("nonce", nonce))
        androidx.core.content.ContextCompat
            .registerReceiver(this, cancelled, android.content.IntentFilter(CANCEL), androidx.core.content.ContextCompat.RECEIVER_NOT_EXPORTED)
        registered = true
        window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
        val url = intent.getStringExtra("url")?.takeIf(AccountLoginPolicy::isAuthorizeUrl) ?: return finish()
        val view =
            runCatching { WebView(this) }.getOrElse {
                setResult(AccountLoginPolicy.RESULT_WEBVIEW_UNAVAILABLE, Intent().putExtra("nonce", nonce))
                return finish()
            }
        webView = view
        val location =
            TextView(this).apply {
                setPadding(20, 16, 20, 16)
                text = AccountLoginPolicy.LOGIN_HOST
            }
        configure(view)
        view.webViewClient = LoginClient(location)
        val layout = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL }
        layout.addView(location)
        layout.addView(view, LinearLayout.LayoutParams(-1, 0, 1f))
        setContentView(layout)
        view.loadUrl(url)
    }

    /** Mirrors the tab WebView settings that sign-in pages depend on; no bridges are installed. */
    @android.annotation.SuppressLint("SetJavaScriptEnabled")
    private fun configure(view: WebView) {
        view.settings.apply {
            javaScriptEnabled = true
            domStorageEnabled = true
            loadWithOverviewMode = true
            useWideViewPort = true
            userAgentString = BROWSER_USER_AGENT
            allowFileAccess = false
            allowContentAccess = false
            // Popups (Google account choosers) hand off in this same view.
            setSupportMultipleWindows(false)
        }
    }

    private fun completeWith(callback: android.net.Uri) {
        // Persist the freshly created Google/UOA session for the tabs before leaving.
        CookieManager.getInstance().flush()
        setResult(RESULT_OK, Intent().setData(callback).putExtra("nonce", nonce))
        finish()
    }

    private inner class LoginClient(
        private val location: TextView,
    ) : WebViewClient() {
        override fun shouldOverrideUrlLoading(
            view: WebView,
            request: WebResourceRequest,
        ): Boolean {
            val next = request.url
            if (AccountLoginPolicy.isCallback(next.scheme, next.host, next.path)) {
                completeWith(next)
                return true
            }
            return !AccountLoginPolicy.allowsNavigation(next.scheme)
        }

        override fun onPageStarted(
            view: WebView,
            url: String,
            favicon: android.graphics.Bitmap?,
        ) {
            val current = android.net.Uri.parse(url)
            location.text = "${current.scheme}://${current.host.orEmpty()}"
        }
    }

    override fun onDestroy() {
        if (registered) unregisterReceiver(cancelled)
        webView?.apply {
            stopLoading()
            destroy()
        }
        webView = null
        super.onDestroy()
    }
}
