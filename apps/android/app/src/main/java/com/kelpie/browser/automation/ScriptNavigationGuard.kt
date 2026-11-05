package com.kelpie.browser.automation

import com.kelpie.browser.handlers.WebViewGuardRejected

/** Recheck authority and Stop only when the renderer callback guard rejected. */
internal suspend fun <T> recheckNavigationGuard(
    stopRequested: () -> Boolean,
    guard: suspend () -> Unit,
    operation: suspend () -> T,
): T =
    try {
        operation()
    } catch (error: WebViewGuardRejected) {
        if (stopRequested()) guard()
        throw error
    }
