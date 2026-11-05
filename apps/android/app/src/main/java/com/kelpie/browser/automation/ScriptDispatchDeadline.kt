package com.kelpie.browser.automation

import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.isActive
import kotlinx.coroutines.withTimeout

/** Retire lost mutation receipts conservatively without retrying input. */
internal suspend fun <T> withScriptDispatchDeadline(
    milliseconds: Long,
    mutating: Boolean,
    classification: ScriptTargetClassification,
    protectUnknown: () -> Unit,
    operation: suspend () -> T,
): T =
    try {
        withTimeout(milliseconds) { operation() }
    } catch (error: Exception) {
        val unknown = classification.unknown()
        if (unknown) protectUnknown()
        if (mutating && unknown && currentCoroutineContext().isActive) throw ScriptFailure("INPUT_UNCERTAIN", true)
        throw error
    }

/** A success without the expected dispatch receipt is not an acknowledgement. */
internal fun requireScriptDispatchReceipt(
    result: Map<String, Any?>,
    protectUnknown: () -> Unit,
) {
    if (result["inputGuarantee"] != "synthetic-coordinate") {
        protectUnknown()
        throw ScriptFailure("INPUT_UNCERTAIN", true)
    }
}
