package com.kelpie.browser.ui

import android.view.MotionEvent
import android.view.ViewGroup
import android.webkit.WebView
import android.widget.FrameLayout
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.viewinterop.AndroidView
import com.kelpie.browser.browser.BrowserState
import com.kelpie.browser.browser.ChromeScrollPolicy
import com.kelpie.browser.browser.TabStore
import com.kelpie.browser.handlers.HandlerContext

/** Displays the active tab's WebView, handles WebView clients, and tracks scroll direction. */
@Composable
fun TabWebViewContent(
    tabStore: TabStore,
    browserState: BrowserState,
    handlerContext: HandlerContext,
    onScrollDirectionChange: (ScrollDirection) -> Unit,
    onScrolled: () -> Unit = {},
    onWebViewReady: (WebView) -> Unit,
    modifier: Modifier = Modifier,
) {
    val scrollCallback by rememberUpdatedState(onScrolled)
    val directionCallback by rememberUpdatedState(onScrollDirectionChange)
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

            val policy = ChromeScrollPolicy()
            var dragging = false
            var translation = 0f
            var start = 0f
            val density = wv.resources.displayMetrics.density
            wv.setOnTouchListener { _, event ->
                when (event.actionMasked) {
                    MotionEvent.ACTION_DOWN -> {
                        start = event.y
                        translation = 0f
                        dragging = true
                        policy.update(0f, 0f, 0f, false)
                    }
                    MotionEvent.ACTION_MOVE -> translation = (event.y - start) / density
                    MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> dragging = false
                }
                false
            }
            wv.setOnScrollChangeListener { _, _, scrollY, _, _ ->
                @Suppress("DEPRECATION")
                val maximum = (wv.contentHeight * wv.scale - wv.height).coerceAtLeast(0f) / density
                policy.update(translation, scrollY / density, maximum, dragging)?.let {
                    directionCallback(if (it) ScrollDirection.DOWN else ScrollDirection.UP)
                }
                scrollCallback()
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
