package com.kelpie.browser.automation

import kotlinx.coroutines.TimeoutCancellationException
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.isActive
import kotlinx.coroutines.withTimeout

/** Distinguish this operation's deadline from cancellation of its owner. */
internal suspend fun <T> withCaptureDeadline(
    milliseconds: Long,
    onTimeout: () -> Unit,
    operation: suspend () -> T,
): T =
    try {
        withTimeout(milliseconds) { operation() }
    } catch (timeout: TimeoutCancellationException) {
        if (!currentCoroutineContext().isActive) throw timeout
        onTimeout()
        throw ScriptFailure("CAPTURE_FAILED")
    }
