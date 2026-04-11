package com.kelpie.browser.browser

import android.annotation.SuppressLint
import android.content.Context
import android.webkit.WebView
import com.kelpie.browser.handlers.HandlerContext
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow

/** Manages the set of open browser tabs. Creates configured WebViews for new tabs. */
class TabStore(
    private val context: Context,
    private val handlerContext: HandlerContext,
) {
    private val _tabs = MutableStateFlow<List<BrowserTab>>(emptyList())
    val tabs: StateFlow<List<BrowserTab>> = _tabs

    private val _activeTabId = MutableStateFlow<String?>(null)
    val activeTabId: StateFlow<String?> = _activeTabId

    val activeTab: BrowserTab?
        get() = _tabs.value.firstOrNull { it.id == _activeTabId.value }

    var pendingRestorationUrls: List<String>? = null
        private set
    private var pendingRestorationActiveIndex: Int = 0

    init {
        val session = SessionStore.load(context)
        val showStartPage =
            !context
                .getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                .getBoolean(KEY_HIDE_WELCOME, false)
        val tab = createTab(isStartPage = session != null || showStartPage)
        _tabs.value = listOf(tab)
        _activeTabId.value = tab.id
        if (session == null && !showStartPage) {
            tab.webView.loadUrl(HomeStore.url)
        }
        if (session != null) {
            pendingRestorationUrls = session.first
            pendingRestorationActiveIndex = session.second
        }
    }

    fun restoreSession() {
        val urls = pendingRestorationUrls ?: return
        val activeIndex = pendingRestorationActiveIndex
        _tabs.value.forEach { it.webView.destroy() }
        val newTabs = urls.map { url -> createTab(isStartPage = false).also { it.webView.loadUrl(url) } }
        _tabs.value = newTabs
        _activeTabId.value = newTabs[minOf(activeIndex, newTabs.size - 1)].id
        pendingRestorationUrls = null
        pendingRestorationActiveIndex = 0
        SessionStore.clear(context)
    }

    fun discardPendingSession() {
        pendingRestorationUrls = null
        SessionStore.clear(context)
    }

    fun addTab(url: String? = null): BrowserTab {
        val tab = createTab()
        _tabs.value = _tabs.value + tab
        _activeTabId.value = tab.id
        if (url != null) {
            tab.isStartPage = false
            tab.webView.loadUrl(url)
        }
        return tab
    }

    fun closeTab(id: String) {
        if (_tabs.value.size <= 1) return
        val index = _tabs.value.indexOfFirst { it.id == id }
        if (index < 0) return
        val removed = _tabs.value[index]
        _tabs.value = _tabs.value.filterNot { it.id == id }
        removed.webView.destroy()
        if (_activeTabId.value == id) {
            _activeTabId.value = _tabs.value[minOf(index, _tabs.value.size - 1)].id
        }
    }

    fun selectTab(id: String) {
        if (_tabs.value.any { it.id == id }) {
            _activeTabId.value = id
        }
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
                addJavascriptInterface(JsBridge(handlerContext, null), "KelpieBridge")
            }
        return BrowserTab(webView = webView, isStartPage = isStartPage)
    }

    companion object {
        private const val PREFS_NAME = "kelpie_prefs"
        private const val KEY_HIDE_WELCOME = "hide_welcome_card"
        private const val BROWSER_USER_AGENT =
            "Mozilla/5.0 (Linux; Android 14; Pixel 8 Pro) AppleWebKit/537.36 " +
                "(KHTML, like Gecko) Version/131.0.0.0 Mobile Safari/537.36"
    }
}
