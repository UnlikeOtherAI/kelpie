package com.kelpie.browser.handlers

import com.kelpie.browser.browser.BrowserTab
import com.kelpie.browser.network.errorResponse

internal fun HandlerContext.diagnosticTab(body: Map<String, Any?>): BrowserTab? {
    val store = tabStore ?: return null
    val id = body["tabId"] as? String ?: return store.activeTab
    return store.tabs.value.firstOrNull { it.id == id }
}

internal fun missingDiagnosticTab(): Map<String, Any?> = errorResponse("TAB_NOT_FOUND", "The requested browser tab is unavailable")
