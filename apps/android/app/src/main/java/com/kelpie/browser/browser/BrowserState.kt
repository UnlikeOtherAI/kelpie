package com.kelpie.browser.browser

import android.webkit.WebView
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

class BrowserState {
    private val _currentUrl = MutableStateFlow(HomeStore.url)
    val currentUrl: StateFlow<String> = _currentUrl.asStateFlow()

    private val _pageTitle = MutableStateFlow("")
    val pageTitle: StateFlow<String> = _pageTitle.asStateFlow()

    private val _isLoading = MutableStateFlow(false)
    val isLoading: StateFlow<Boolean> = _isLoading.asStateFlow()

    private val _canGoBack = MutableStateFlow(false)
    val canGoBack: StateFlow<Boolean> = _canGoBack.asStateFlow()

    private val _canGoForward = MutableStateFlow(false)
    val canGoForward: StateFlow<Boolean> = _canGoForward.asStateFlow()

    private val _progress = MutableStateFlow(0)
    val progress: StateFlow<Int> = _progress.asStateFlow()

    var webView: WebView? = null

    fun updateUrl(url: String) { _currentUrl.value = url }
    fun updateTitle(title: String) { _pageTitle.value = title }
    fun updateLoading(loading: Boolean) { _isLoading.value = loading }
    fun updateCanGoBack(can: Boolean) { _canGoBack.value = can }
    fun updateCanGoForward(can: Boolean) { _canGoForward.value = can }
    fun updateProgress(p: Int) { _progress.value = p }
}
