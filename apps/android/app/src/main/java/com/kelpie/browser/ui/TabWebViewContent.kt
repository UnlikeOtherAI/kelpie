package com.kelpie.browser.ui

import android.view.ViewGroup
import android.webkit.WebView
import android.widget.FrameLayout
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.viewinterop.AndroidView
import com.kelpie.browser.browser.BrowserState
import com.kelpie.browser.browser.TabStore
import com.kelpie.browser.handlers.HandlerContext

/** Displays the active tab's WebView, handles WebView clients, and tracks scroll direction. */
@Composable
fun TabWebViewContent(
    tabStore: TabStore,
    browserState: BrowserState,
    handlerContext: HandlerContext,
    onScrollDirectionChange: (ScrollDirection) -> Unit,
    onWebViewReady: (WebView) -> Unit,
    modifier: Modifier = Modifier,
) {
    val tabs by tabStore.tabs.collectAsState()
    val activeTabId by tabStore.activeTabId.collectAsState()
    val installedWebViewRef = remember { mutableStateOf<WebView?>(null) }

    AndroidView(
        factory = { ctx -> FrameLayout(ctx) },
        update = { container ->
            val tab = tabs.firstOrNull { it.id == activeTabId } ?: return@AndroidView
            val wv = tab.webView

            if (wv === installedWebViewRef.value) return@AndroidView

            container.removeAllViews()
            (wv.parent as? ViewGroup)?.removeView(wv)

            container.addView(
                wv,
                FrameLayout.LayoutParams(
                    ViewGroup.LayoutParams.MATCH_PARENT,
                    ViewGroup.LayoutParams.MATCH_PARENT,
                ),
            )

            wv.setOnScrollChangeListener { _, _, scrollY, _, oldScrollY ->
                val delta = scrollY - oldScrollY
                if (scrollY <= 0) {
                    onScrollDirectionChange(ScrollDirection.UP)
                } else if (delta > 12) {
                    onScrollDirectionChange(ScrollDirection.DOWN)
                } else if (delta < -12) {
                    onScrollDirectionChange(ScrollDirection.UP)
                }
            }

            syncBrowserStateFromWebView(wv, browserState)
            installedWebViewRef.value = wv
            onWebViewReady(wv)
        },
        modifier = modifier,
    )
}

private fun syncBrowserStateFromWebView(
    webView: WebView,
    browserState: BrowserState,
) {
    browserState.updateUrl(webView.url ?: "")
    browserState.updateTitle(webView.title ?: "")
    browserState.updateCanGoBack(webView.canGoBack())
    browserState.updateCanGoForward(webView.canGoForward())
    browserState.webView = webView
}
