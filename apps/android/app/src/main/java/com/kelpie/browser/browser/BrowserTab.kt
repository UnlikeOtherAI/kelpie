package com.kelpie.browser.browser

import android.graphics.Bitmap
import android.webkit.WebView
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import java.util.UUID

/** A single browser tab. Owns a WebView and tracks its page state. */
class BrowserTab(
    val id: String = UUID.randomUUID().toString(),
    val webView: WebView,
    var isStartPage: Boolean = true,
) {
    var currentUrl: String by mutableStateOf("")
    var pageTitle: String by mutableStateOf("")
    var isLoading: Boolean by mutableStateOf(false)
    var chromeColor: Int by mutableStateOf(-1)
    var preview: Bitmap? by mutableStateOf(null)

    private var lastHistoryUrl: String = ""
    private var lastHistoryTitle: String = ""
    private var lastObservedHistoryClearGeneration: Int = HistoryStore.clearGeneration

    fun recordHistoryIfNeeded(url: String) {
        syncHistoryTrackingIfNeeded()
        val trimmedUrl = url.trim()
        if (trimmedUrl.isEmpty() || trimmedUrl == lastHistoryUrl) {
            return
        }

        lastHistoryUrl = trimmedUrl
        lastHistoryTitle = pageTitle.trim()
        HistoryStore.record(trimmedUrl, pageTitle)
    }

    fun updateHistoryTitleIfNeeded(title: String) {
        syncHistoryTrackingIfNeeded()
        val trimmedUrl = currentUrl.trim()
        val trimmedTitle = title.trim()
        if (trimmedUrl.isEmpty() || trimmedTitle.isEmpty()) {
            return
        }
        if (trimmedUrl != lastHistoryUrl || trimmedTitle == lastHistoryTitle) {
            return
        }

        lastHistoryTitle = trimmedTitle
        HistoryStore.updateLatestTitle(trimmedUrl, trimmedTitle)
    }

    private fun syncHistoryTrackingIfNeeded() {
        val currentGeneration = HistoryStore.clearGeneration
        if (currentGeneration == lastObservedHistoryClearGeneration) {
            return
        }
        lastObservedHistoryClearGeneration = currentGeneration
        lastHistoryUrl = ""
        lastHistoryTitle = ""
    }
}
