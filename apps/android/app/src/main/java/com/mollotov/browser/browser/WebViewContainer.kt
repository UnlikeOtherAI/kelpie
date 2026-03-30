package com.mollotov.browser.browser

import android.annotation.SuppressLint
import android.graphics.Bitmap
import android.webkit.WebChromeClient
import android.webkit.WebResourceRequest
import android.webkit.WebView
import android.webkit.WebViewClient
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.viewinterop.AndroidView
import com.mollotov.browser.devtools.ConsoleHandler

@SuppressLint("SetJavaScriptEnabled")
@Composable
fun WebViewContainer(
    browserState: BrowserState,
    modifier: Modifier = Modifier,
    consoleHandler: ConsoleHandler? = null,
    onWebViewCreated: (WebView) -> Unit = {},
) {
    AndroidView(
        factory = { context ->
            WebView(context).apply {
                settings.javaScriptEnabled = true
                settings.domStorageEnabled = true
                settings.loadWithOverviewMode = true
                settings.useWideViewPort = true
                settings.setSupportMultipleWindows(false)
                settings.mediaPlaybackRequiresUserGesture = false
                settings.userAgentString = "Mozilla/5.0 (Linux; Android 14; Pixel 8 Pro) AppleWebKit/537.36 (KHTML, like Gecko) Version/131.0.0.0 Mobile Safari/537.36"

                // Add JS bridge for console + network capture
                addJavascriptInterface(JsBridge(consoleHandler), "MollotovBridge")

                webViewClient = object : WebViewClient() {
                    override fun onPageStarted(view: WebView, url: String, favicon: Bitmap?) {
                        browserState.updateUrl(url)
                        browserState.updateLoading(true)
                    }

                    override fun onPageFinished(view: WebView, url: String) {
                        browserState.updateUrl(url)
                        browserState.updateLoading(false)
                        browserState.updateCanGoBack(view.canGoBack())
                        browserState.updateCanGoForward(view.canGoForward())

                        // Inject bridge scripts after page load
                        view.evaluateJavascript(ConsoleHandler.BRIDGE_SCRIPT, null)
                        view.evaluateJavascript(JsBridge.NETWORK_BRIDGE_SCRIPT, null)
                    }

                    override fun shouldOverrideUrlLoading(view: WebView, request: WebResourceRequest): Boolean {
                        return false
                    }
                }

                webChromeClient = object : WebChromeClient() {
                    override fun onReceivedTitle(view: WebView, title: String?) {
                        browserState.updateTitle(title ?: "")
                    }

                    override fun onProgressChanged(view: WebView, newProgress: Int) {
                        browserState.updateProgress(newProgress)
                    }
                }

                browserState.webView = this
                onWebViewCreated(this)

                loadUrl(browserState.currentUrl.value)
            }
        },
        modifier = modifier,
    )
}
