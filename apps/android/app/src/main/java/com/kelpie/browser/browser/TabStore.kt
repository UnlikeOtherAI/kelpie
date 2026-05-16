package com.kelpie.browser.browser

import android.annotation.SuppressLint
import android.content.Context
import android.webkit.WebView
import com.kelpie.browser.handlers.HandlerContext
import com.kelpie.browser.handlers.WebSocketHandler
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow

/** Manages the set of open browser tabs. Creates configured WebViews for new tabs. */
class TabStore(
    private val context: Context,
    private val handlerContext: HandlerContext,
    private val browserState: BrowserState,
) {
    private val _tabs = MutableStateFlow<List<BrowserTab>>(emptyList())
    val tabs: StateFlow<List<BrowserTab>> = _tabs

    private val _activeTabId = MutableStateFlow<String?>(null)
    val activeTabId: StateFlow<String?> = _activeTabId

    val activeTab: BrowserTab?
        get() = _tabs.value.firstOrNull { it.id == _activeTabId.value }

    init {
        val session = SessionStore.load(context)
        if (session != null) {
            val restoredTabs = restoredTabs(session.first)
            if (restoredTabs.isNotEmpty()) {
                _tabs.value = restoredTabs
                _activeTabId.value = restoredTabs[minOf(session.second, restoredTabs.size - 1)].id
            }
        }
        if (_tabs.value.isEmpty()) {
            val showStartPage =
                !context
                    .getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                    .getBoolean(KEY_HIDE_WELCOME, false)
            val tab = createTab(isStartPage = showStartPage)
            _tabs.value = listOf(tab)
            _activeTabId.value = tab.id
            if (!showStartPage) {
                tab.webView.loadUrl(HomeStore.url)
            }
        }
    }

    fun addTab(url: String? = null): BrowserTab {
        val tab = createTab()
        _tabs.value = _tabs.value + tab
        _activeTabId.value = tab.id
        if (url != null) {
            tab.isStartPage = false
            tab.currentUrl = url
            tab.webView.loadUrl(url)
        }
        persistSession()
        return tab
    }

    fun closeTab(id: String) {
        val index = _tabs.value.indexOfFirst { it.id == id }
        if (index < 0) return

        if (_tabs.value.size == 1) {
            val replacement = createTab()
            val currentTab = _tabs.value.first()
            destroyWebView(currentTab.webView)
            _tabs.value = listOf(replacement)
            _activeTabId.value = replacement.id
            persistSession()
            return
        }

        val removed = _tabs.value[index]
        _tabs.value = _tabs.value.filterNot { it.id == id }
        destroyWebView(removed.webView)
        if (_activeTabId.value == id) {
            _activeTabId.value = _tabs.value[minOf(index, _tabs.value.size - 1)].id
        }
        persistSession()
    }

    fun selectTab(id: String) {
        if (_tabs.value.any { it.id == id }) {
            _activeTabId.value = id
            persistSession()
        }
    }

    /**
     * Destroys every tab's WebView. Call this from the Activity's onDestroy so per-tab WebView,
     * JavaScript interface, and WebChromeClient references do not leak across Activity recreation.
     */
    fun destroyAllTabs() {
        val snapshot = _tabs.value
        _tabs.value = emptyList()
        _activeTabId.value = null
        snapshot.forEach { destroyWebView(it.webView) }
    }

    @SuppressLint("SetJavaScriptEnabled")
    private fun createTab(isStartPage: Boolean = true): BrowserTab {
        val webView =
            WebView(context).apply {
                settings.javaScriptEnabled = true
                settings.domStorageEnabled = true
                settings.loadWithOverviewMode = true
                settings.useWideViewPort = true
                settings.setSupportMultipleWindows(false)
                settings.mediaPlaybackRequiresUserGesture = false
                settings.userAgentString = BROWSER_USER_AGENT
                addJavascriptInterface(JsBridge(handlerContext), JS_BRIDGE_NAME)
                WebSocketHandler.installBridge(this)
            }
        val tab = BrowserTab(webView = webView, isStartPage = isStartPage)
        installTabWebViewClients(webView, tab, this, browserState, handlerContext)
        return tab
    }

    private fun destroyWebView(webView: WebView) {
        try {
            webView.removeJavascriptInterface(JS_BRIDGE_NAME)
        } catch (_: Exception) {
        }
        webView.destroy()
    }

    private fun restoredTabs(urls: List<String>): List<BrowserTab> =
        urls.map { url ->
            createTab(isStartPage = false).also {
                it.currentUrl = url
                it.webView.loadUrl(url)
            }
        }

    fun persistSession() {
        SessionStore.save(context, _tabs.value, _activeTabId.value)
    }

    companion object {
        private const val PREFS_NAME = "kelpie_prefs"
        private const val KEY_HIDE_WELCOME = "hide_welcome_card"
        private const val JS_BRIDGE_NAME = "KelpieBridge"
        private const val BROWSER_USER_AGENT =
            "Mozilla/5.0 (Linux; Android 14; Pixel 8 Pro) AppleWebKit/537.36 " +
                "(KHTML, like Gecko) Version/131.0.0.0 Mobile Safari/537.36"
    }
}
