package com.kelpie.browser.browser

import android.graphics.Bitmap
import android.webkit.WebChromeClient
import android.webkit.WebResourceError
import android.webkit.WebResourceRequest
import android.webkit.WebResourceResponse
import android.webkit.WebView
import android.webkit.WebViewClient
import com.kelpie.browser.handlers.ConsoleHandler
import com.kelpie.browser.handlers.HandlerContext
import com.kelpie.browser.handlers.WebSocketHandler
import com.kelpie.browser.network.isLoopbackHost

/**
 * Installs the WebViewClient and WebChromeClient for a tab's WebView. Per-tab state (URL, title,
 * loading, history) is always updated on the [BrowserTab]. The shared [BrowserState] used by the
 * URL bar is only updated when the tab is currently active in [tabStore], so background loads
 * never clobber the active tab's UI.
 */
internal fun installTabWebViewClients(
    webView: WebView,
    tab: BrowserTab,
    tabStore: TabStore,
    browserState: BrowserState,
    handlerContext: HandlerContext,
) {
    val isActive: () -> Boolean = { tabStore.activeTabId.value == tab.id }

    webView.webViewClient = tabWebViewClient(tab, tabStore, browserState, handlerContext, isActive)
    webView.webChromeClient = tabWebChromeClient(tab, tabStore, browserState, handlerContext, isActive)
}

private fun tabWebViewClient(
    tab: BrowserTab,
    tabStore: TabStore,
    browserState: BrowserState,
    handlerContext: HandlerContext,
    isActive: () -> Boolean,
): WebViewClient =
    object : WebViewClient() {
        private var documentNavigationUrl: String? = null
        private var didCaptureDocumentForNavigation = false

        override fun onPageStarted(
            view: WebView,
            url: String,
            favicon: Bitmap?,
        ) {
            val previousVersion = tab.documentVersion
            tab.documentVersion =
                java.util.UUID
                    .randomUUID()
                    .toString()
            tab.remoteNavigationLease?.started(previousVersion, tab.documentVersion, url)
            handlerContext.browserDocumentChanged?.invoke(tab.id)
            if (isActive()) {
                handlerContext.dialogState.dismissPending()
            }
            tab.diagnostics.navigationError = null
            tab.currentUrl = url
            tab.recordHistoryIfNeeded(url)
            tab.isLoading = true
            tabStore.persistSession()
            if (isActive()) {
                browserState.updateUrl(url)
                browserState.updateProgress(view.progress)
                browserState.updateLoading(true)
                handlerContext.mark3DInspectorInactive()
            }
            tab.diagnostics.documentResponse = null
            documentNavigationUrl = url
            didCaptureDocumentForNavigation = false
        }

        override fun onReceivedError(
            view: WebView,
            request: WebResourceRequest?,
            error: WebResourceError?,
        ) {
            if (request?.isForMainFrame != true) return
            val description = error?.description?.toString() ?: "Navigation failed"
            val host = request.url.host
            val cannotReachHost = error?.errorCode == WebViewClient.ERROR_CONNECT || error?.errorCode == WebViewClient.ERROR_HOST_LOOKUP
            tab.diagnostics.navigationError =
                if (cannotReachHost && host != null && isLoopbackHost(host)) {
                    "$description. Loopback addresses refer to the device running Kelpie. " +
                        "Check that the server is listening there, or use the server's LAN address if it runs on another machine."
                } else {
                    description
                }
        }

        override fun onReceivedHttpError(
            view: WebView,
            request: WebResourceRequest?,
            errorResponse: WebResourceResponse?,
        ) {
            if (request?.isForMainFrame != true) return
            val code = errorResponse?.statusCode ?: return
            tab.diagnostics.documentResponse = DocumentResponse(request.url.toString(), code, errorResponse.mimeType)
            if (code >= 400) {
                tab.diagnostics.navigationError = "HTTP $code"
            }
        }

        override fun onPageFinished(
            view: WebView,
            url: String,
        ) {
            tab.currentUrl = url
            tab.recordHistoryIfNeeded(url)
            tab.isLoading = false
            tabStore.persistSession()
            // Only the default store syncs; partitioned tabs never feed cookie sync.
            if (tab.partition == null) {
                com.kelpie.browser.sync.CookieSync
                    .pageLoaded(url)
            }
            if (isActive()) {
                browserState.updateUrl(url)
                browserState.updateLoading(false)
                browserState.updateCanGoBack(view.canGoBack())
                browserState.updateCanGoForward(view.canGoForward())
            }

            view.evaluateJavascript(JsBridge.NETWORK_BRIDGE_SCRIPT, null)
            view.evaluateJavascript(ConsoleHandler.BRIDGE_SCRIPT, null)
            if (!WebSocketHandler.isDocumentStartSupported) {
                view.evaluateJavascript(WebSocketHandler.BRIDGE_SCRIPT, null)
            }

            if (!didCaptureDocumentForNavigation && documentNavigationUrl == url) {
                didCaptureDocumentForNavigation = true
                view.evaluateJavascript("(document.contentType || 'text/html')") { value ->
                    val contentType =
                        value
                            ?.trim()
                            ?.removePrefix("\"")
                            ?.removeSuffix("\"")
                            ?.takeIf { it.isNotEmpty() && it != "null" }
                            ?: "text/html"
                    NetworkTrafficStore.appendDocumentNavigation(
                        url = url,
                        statusCode = 0,
                        contentType = contentType,
                    )
                }
            }
        }

        override fun shouldOverrideUrlLoading(
            view: WebView,
            request: WebResourceRequest,
        ): Boolean = false
    }

private fun tabWebChromeClient(
    tab: BrowserTab,
    tabStore: TabStore,
    browserState: BrowserState,
    handlerContext: HandlerContext,
    isActive: () -> Boolean,
): WebChromeClient =
    object : WebChromeClient() {
        override fun onReceivedTitle(
            view: WebView,
            title: String?,
        ) {
            val nextTitle = title ?: ""
            tab.pageTitle = nextTitle
            tab.updateHistoryTitleIfNeeded(nextTitle)
            tabStore.persistSession()
            if (isActive()) {
                browserState.updateTitle(nextTitle)
            }
        }

        override fun onProgressChanged(
            view: WebView,
            newProgress: Int,
        ) {
            if (isActive()) {
                browserState.updateProgress(newProgress)
            }
        }

        override fun onJsAlert(
            view: WebView,
            url: String?,
            message: String?,
            result: android.webkit.JsResult,
        ): Boolean {
            handlerContext.dialogState.enqueue(
                DialogState.PendingDialog(
                    type = "alert",
                    message = message.orEmpty(),
                    defaultText = null,
                    jsResult = result,
                    jsPromptResult = null,
                ),
            )
            return true
        }

        override fun onJsConfirm(
            view: WebView,
            url: String?,
            message: String?,
            result: android.webkit.JsResult,
        ): Boolean {
            handlerContext.dialogState.enqueue(
                DialogState.PendingDialog(
                    type = "confirm",
                    message = message.orEmpty(),
                    defaultText = null,
                    jsResult = result,
                    jsPromptResult = null,
                ),
            )
            return true
        }

        override fun onJsPrompt(
            view: WebView,
            url: String?,
            message: String?,
            defaultValue: String?,
            result: android.webkit.JsPromptResult,
        ): Boolean {
            handlerContext.dialogState.enqueue(
                DialogState.PendingDialog(
                    type = "prompt",
                    message = message.orEmpty(),
                    defaultText = defaultValue,
                    jsResult = null,
                    jsPromptResult = result,
                ),
            )
            return true
        }
    }
