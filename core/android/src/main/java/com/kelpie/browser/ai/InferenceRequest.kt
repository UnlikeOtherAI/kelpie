package com.kelpie.browser.ai

import com.kelpie.browser.nativecore.NativeCore

/** One immutable cancellation flag; it cannot cancel a different engine request. */
class InferenceRequest : AutoCloseable {
    val handle = NativeCore.inferenceRequestCreate().also { check(it != 0L) }

    fun cancel() = NativeCore.inferenceRequestCancel(handle)

    override fun close() = NativeCore.inferenceRequestDestroy(handle)
}
