package com.kelpie.browser.network

import com.kelpie.browser.ai.openai.OpenAIJson
import com.kelpie.browser.nativecore.BrowserGatewayAbi
import com.kelpie.browser.nativecore.BrowserGatewayNative
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withTimeout
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject

/** Serializes authorization and the complete native transaction, without reimplementing its validator. */
class BrowserGatewaySession(
    config: Map<String, Any?>,
    private val lock: Mutex,
    private val authorize: suspend (Map<String, Any?>, Boolean) -> Boolean,
    private val dispatch: suspend (String, Map<String, Any?>) -> Map<String, Any?>,
    private val abi: BrowserGatewayAbi = BrowserGatewayNative,
    private val dispatchTimeoutMs: Long = 30_000,
    private val beforeBegin: () -> Unit = {},
    private val beforeMutation: () -> Unit = {},
) {
    private var handle = abi.create(OpenAIJson.encode(OpenAIJson.fromAny(config))).also { check(it != 0L) }

    suspend fun call(
        request: Map<String, Any?>,
        mcp: Boolean = false,
    ): Map<String, Any?>? =
        lock.withLock {
            check(handle != 0L) { "The browser gateway has closed" }
            beforeBegin()
            var step = decode(abi.begin(handle, OpenAIJson.encode(OpenAIJson.fromAny(request)), mcp))
            try {
                while (step["kind"] != "complete") {
                    val result =
                        when (step["kind"]) {
                            "authorize" -> mapOf("success" to authorize(objectValue(step["request"]), step["mutates"] == true))
                            "dispatch" ->
                                withTimeout(dispatchTimeoutMs) {
                                    if (step["mutates"] == true) beforeMutation()
                                    dispatch(step["method"] as String, objectValue(step["params"]))
                                }
                            else -> error("Invalid native browser step")
                        }
                    step = decode(abi.advance(handle, OpenAIJson.encode(OpenAIJson.fromAny(result))))
                }
                response(step)
            } catch (error: Exception) {
                val cancelled = response(decode(abi.cancel(handle)))
                if (error is CancellationException && error !is kotlinx.coroutines.TimeoutCancellationException) throw error
                cancelled
            }
        }

    /** Called under the same router lock before legacy mutations touch the renderer. */
    fun invalidateLocked(tabId: String? = null) {
        if (handle != 0L) abi.invalidate(handle, tabId)
    }

    suspend fun close() =
        lock.withLock {
            if (handle != 0L) {
                abi.destroy(handle)
                handle = 0
            }
        }

    private fun decode(text: String): Map<String, Any?> = OpenAIJson.toMap(checkNotNull(OpenAIJson.parseObjectOrNull(text)))

    private fun response(step: Map<String, Any?>): Map<String, Any?>? = if (step["response"] == null || step["response"] == JsonNull) null else objectValue(step["response"])

    private fun objectValue(value: Any?): Map<String, Any?> =
        when (value) {
            is JsonObject -> OpenAIJson.toMap(value)
            is Map<*, *> -> value.entries.associate { (key, item) -> checkNotNull(key as? String) to item }
            else -> error("Invalid browser object")
        }
}
