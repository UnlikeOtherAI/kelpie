package com.mollotov.browser.browser

import android.graphics.Bitmap
import android.webkit.WebChromeClient
import android.webkit.WebResourceRequest
import android.webkit.WebView
import android.webkit.WebViewClient
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.viewinterop.AndroidView

@Composable
fun WebViewContainer(
    browserState: BrowserState,
    modifier: Modifier = Modifier,
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
