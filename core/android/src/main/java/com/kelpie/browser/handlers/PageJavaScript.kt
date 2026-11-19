package com.kelpie.browser.handlers

import kotlinx.coroutines.delay
import kotlinx.coroutines.withTimeoutOrNull
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.longOrNull
import java.util.UUID

/** Android WebView delivers the immediate value, so read an asynchronous result on the admitted WebView. */
internal object PageJavaScript {
    private const val TIMEOUT_MS = 30_000L

    suspend fun evaluate(
        source: String,
        run: suspend (String) -> String,
    ): Any? {
        val key = JsonPrimitive("__kelpieEval_${UUID.randomUUID()}").toString()
        val result =
            withTimeoutOrNull(TIMEOUT_MS) {
                var reply = decode(run(startScript(source, key)))
                while (reply["pending"] != null) {
                    delay(50)
                    reply = decode(run(readResultScript(key)))
                }
                reply
            } ?: error("JavaScript evaluation timed out")

        if (result["blocked"] != null) {
            return toAny(Json.parseToJsonElement(run(source)))
        }
        (result["error"] as? JsonPrimitive)?.let { error(it.content) }
        return toAny(result["value"])
    }

    private fun startScript(
        source: String,
        key: String,
    ): String =
        """
        (() => {
            const evaluate = window.eval;
            const failure = error => ({error: String(error)});
            try {
                evaluate("void 0");
            } catch (error) {
                // The page can prohibit string compilation. No user code has run.
                return error instanceof EvalError ? {blocked: true} : failure(error);
            }
            try {
                const value = evaluate(${JsonPrimitive(source)});
                if (value == null || typeof value.then !== "function") return {value: value == null ? null : value};
                // Keep only pending evaluations in the page. Expire the slot even if the client leaves.
                const slot = {result: {pending: true}, expiry: setTimeout(() => delete window[$key], $TIMEOUT_MS)};
                Object.defineProperty(window, $key, {value: slot, configurable: true});
                Promise.resolve(value).then(
                    resolved => { slot.result = {value: resolved == null ? null : resolved}; },
                    error => { slot.result = failure(error); }
                );
                return slot.result;
            } catch (error) {
                return failure(error);
            }
        })()
        """.trimIndent()

    private fun decode(raw: String): JsonObject = Json.parseToJsonElement(raw) as? JsonObject ?: error("Invalid JavaScript evaluation result")

    private fun readResultScript(key: String): String =
        """
        (() => {
            const slot = window[$key];
            if (!slot) return {error: "Page changed during JavaScript evaluation"};
            if (slot.result.pending) return slot.result;
            delete window[$key];
            clearTimeout(slot.expiry);
            return slot.result;
        })()
        """.trimIndent()

    private fun toAny(element: JsonElement?): Any? =
        when (element) {
            null, JsonNull -> null
            is JsonPrimitive ->
                if (element.isString) {
                    element.content
                } else {
                    element.booleanOrNull ?: element.intOrNull ?: element.longOrNull ?: element.doubleOrNull
                }
            is JsonObject -> element.entries.associate { (key, value) -> key to toAny(value) }
            is JsonArray -> element.map(::toAny)
        }
}
