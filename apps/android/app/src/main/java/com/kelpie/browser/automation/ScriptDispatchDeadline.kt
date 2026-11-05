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

/** Classify the callback before authority/tab guards can suppress its body. */
internal fun scriptDispatchReceiptWellFormed(
    result: Map<String, Any?>,
    token: String?,
): Boolean =
    when (result["ok"]) {
        true ->
            token != null &&
                result["token"] == token &&
                result["mayHaveCompleted"] == true &&
                result["inputGuarantee"] == "synthetic-coordinate"
        false -> result["error"] is String && result["mayHaveCompleted"] is Boolean
        else -> false
    }

internal fun protectMalformedScriptReceipt(
    result: Map<String, Any?>,
    token: String?,
    protect: () -> Unit,
) {
    if (!scriptDispatchReceiptWellFormed(result, token)) protect()
}

/** A success without the expected dispatch receipt is not an acknowledgement. */
internal fun requireScriptDispatchReceipt(
    result: Map<String, Any?>,
    token: String?,
    protectUnknown: () -> Unit,
) {
    if (result["ok"] != true || !scriptDispatchReceiptWellFormed(result, token)) {
        protectUnknown()
        throw ScriptFailure("INPUT_UNCERTAIN", true)
    }
}
