package com.kelpie.browser.handlers

import com.kelpie.browser.network.Router
import com.kelpie.browser.network.errorResponse
import com.kelpie.browser.network.successResponse
import kotlinx.coroutines.delay
import java.io.File

class ScriptHandler(
    private val ctx: HandlerContext,
    private val router: Router,
    private val playbackState: ScriptPlaybackState,
) {
    fun register(router: Router) {
        router.register("play-script") { playScript(it) }
        router.register("abort-script") { abortScript() }
        router.register("get-script-status") { getScriptStatus() }
    }

    private suspend fun playScript(body: Map<String, Any?>): Map<String, Any?> {
        val actions = actionList(body["actions"]) ?: return errorResponse("MISSING_PARAM", "actions is required")
        if (actions.isEmpty()) return errorResponse("MISSING_PARAM", "actions is required")
        val continueOnError = body["continueOnError"] as? Boolean ?: false
        val defaultWaitBetweenActions = body["defaultWaitBetweenActions"] as? Int ?: 0
        val overlayColor = body["overlayColor"] as? String ?: "#3B82F6"

        if (!playbackState.start(totalActions = actions.size, continueOnError = continueOnError)) {
            return errorResponse("RECORDING_IN_PROGRESS", "Script is playing. Call abort-script to stop.")
        }

        if (ctx.isIn3DInspector) {
            runCatching { ctx.evaluateJS(com.kelpie.browser.handlers.Snapshot3DBridge.EXIT_SCRIPT) }
            ctx.mark3DInspectorInactive()
        }

        return runScript(
            actions = actions,
            overlayColor = overlayColor,
            defaultWaitBetweenActions = defaultWaitBetweenActions,
            continueOnError = continueOnError,
        )
    }

    private fun abortScript(): Map<String, Any?> = playbackState.requestAbort() ?: errorResponse("NO_SCRIPT_RUNNING", "No script is currently playing")

    private fun getScriptStatus(): Map<String, Any?> = playbackState.statusResponse()

    private suspend fun runScript(
        actions: List<Map<String, Any?>>,
        overlayColor: String,
        defaultWaitBetweenActions: Int,
        continueOnError: Boolean,
    ): Map<String, Any?> {
        for ((index, action) in actions.withIndex()) {
            if (playbackState.isAbortRequested()) {
                return playbackState.finishAborted()
            }

            val actionName = action["action"] as? String
            if (actionName.isNullOrBlank()) {
                playbackState.recordFailure(
                    index = index,
                    action = "unknown",
                    code = "INVALID_ACTION",
                    message = "Each action requires an action name",
                    skipped = false,
                )
                return playbackState.finishFatalFailure("INVALID_ACTION", "Each action requires an action name")
            }

            playbackState.updateCurrentAction(index, actionName)
            val response = executeAction(action, actionName, overlayColor)
            if (isAbortResponse(response)) {
                return playbackState.finishAborted()
            }

            val succeeded = response["success"] as? Boolean ?: false
            if (actionName == "screenshot" && succeeded) {
                saveScreenshot(response, index)?.let {
                    playbackState.addScreenshot(it.index, it.file, it.width, it.height)
                }
            }

            if (succeeded) {
                playbackState.recordSuccess(index)
            } else {
                val error = errorDetails(response)
                playbackState.recordFailure(
                    index = index,
                    action = actionName,
                    code = error.first,
                    message = error.second,
                    skipped = continueOnError,
                )
                if (!continueOnError) {
                    return playbackState.finishFatalFailure(error.first, error.second)
                }
            }

            if (playbackState.isAbortRequested()) {
                return playbackState.finishAborted()
            }

            val shouldPause =
                defaultWaitBetweenActions > 0 &&
                    index < actions.lastIndex &&
                    ((actions[index + 1]["action"] as? String) !in setOf("wait", "wait-for-element", "wait-for-navigation"))
            if (shouldPause && !sleepWithAbortCheck(defaultWaitBetweenActions)) {
                return playbackState.finishAborted()
            }
        }

        return playbackState.finishSuccess()
    }

    private suspend fun executeAction(
        action: Map<String, Any?>,
        actionName: String,
        overlayColor: String,
    ): Map<String, Any?> {
        return when (actionName) {
            "wait" -> {
                val milliseconds = action["ms"] as? Int ?: return errorResponse("MISSING_PARAM", "ms is required")
                if (!sleepWithAbortCheck(milliseconds)) abortResponse() else successResponse(mapOf("waitedMs" to milliseconds))
            }

            "wait-for-element" -> waitForElement(action)

            "wait-for-navigation" -> waitForNavigation(action)

            else -> {
                val method = forwardedMethod(actionName)
                if (method.isEmpty()) {
                    errorResponse("INVALID_ACTION", "Unsupported action: $actionName")
                } else {
                    router.handle(method, forwardedBody(action, actionName, overlayColor), bypassRecordingGate = true).second
                }
            }
        }
    }

    private fun forwardedMethod(actionName: String): String =
        when (actionName) {
            "commentary" -> "show-commentary"
            else -> actionName
        }

    private fun forwardedBody(
        action: Map<String, Any?>,
        actionName: String,
        overlayColor: String,
    ): Map<String, Any?> {
        val body = action.toMutableMap()
        body.remove("action")

        when (actionName) {
            "evaluate" -> {
                if (body["expression"] == null && body["script"] != null) {
                    body["expression"] = body.remove("script")
                }
            }

            "handle-dialog" -> {
                if (body["promptText"] == null && body["text"] != null) {
                    body["promptText"] = body.remove("text")
                }
            }
        }

        if (actionName in setOf("click", "tap", "fill", "type", "select-option", "check", "uncheck", "swipe") &&
            body["color"] == null
        ) {
            body["color"] = overlayColor
        }
        return body
    }

    private suspend fun waitForElement(body: Map<String, Any?>): Map<String, Any?> {
        val selector = body["selector"] as? String ?: return errorResponse("MISSING_PARAM", "selector is required")
        val timeout = body["timeout"] as? Int ?: 5000
        val state = body["state"] as? String ?: "visible"
        val startedAt = System.currentTimeMillis()
        repeat(maxOf(timeout / 100, 1)) {
            if (playbackState.isAbortRequested()) return abortResponse()
            val js =
                """
                (function() {
                    var el = document.querySelector('${JSEscape.string(selector)}');
                    if (!el) return null;
                    var rect = el.getBoundingClientRect();
                    var visible = rect.width > 0 && rect.height > 0;
                    return {tag: el.tagName.toLowerCase(), classes: Array.from(el.classList), visible: visible};
                })()
                """.trimIndent()
            val result = runCatching { ctx.evaluateJSReturningJSON(js) }.getOrDefault(emptyMap())
            if (result.isNotEmpty()) {
                val visible = result["visible"] as? Boolean ?: false
                val matches = state == "attached" || (state == "visible" && visible) || (state == "hidden" && !visible)
                if (matches) {
                    return successResponse(
                        mapOf(
                            "element" to result,
                            "waitTime" to (System.currentTimeMillis() - startedAt),
                        ),
                    )
                }
            } else if (state == "hidden") {
                return successResponse(mapOf("detached" to true, "waitTime" to (System.currentTimeMillis() - startedAt)))
            }
            if (!sleepWithAbortCheck(100)) return abortResponse()
        }
        return errorResponse("TIMEOUT", "Element did not reach state '$state' within ${timeout}ms")
    }

    private suspend fun waitForNavigation(body: Map<String, Any?>): Map<String, Any?> {
        if (ctx.webView == null) return errorResponse("NO_WEBVIEW", "No WebView")
        val timeout = body["timeout"] as? Int ?: 10000
        val startedAt = System.currentTimeMillis()
        val initial =
            runCatching {
                ctx.evaluateJSReturningJSON("({readyState: document.readyState, url: location.href, title: document.title})")
            }.getOrDefault(emptyMap())
        val initialUrl = initial["url"] as? String
        var observedLoading = initial["readyState"] != "complete"

        repeat(maxOf(timeout / 100, 1)) {
            if (playbackState.isAbortRequested()) return abortResponse()
            val result =
                runCatching {
                    ctx.evaluateJSReturningJSON("({readyState: document.readyState, url: location.href, title: document.title})")
                }.getOrDefault(emptyMap())
            val readyState = result["readyState"] as? String ?: ""
            val currentUrl = result["url"] as? String ?: ""
            if (readyState != "complete" || (initialUrl != null && currentUrl != initialUrl)) {
                observedLoading = true
            }
            if (observedLoading && readyState == "complete") {
                return successResponse(
                    mapOf(
                        "url" to currentUrl,
                        "title" to (result["title"] ?: ""),
                        "loadTime" to (System.currentTimeMillis() - startedAt),
                    ),
                )
            }
            if (!sleepWithAbortCheck(100)) return abortResponse()
        }
        return errorResponse("TIMEOUT", "Navigation did not complete within ${timeout}ms")
    }

    private fun abortResponse(): Map<String, Any?> =
        mapOf(
            "success" to false,
            "aborted" to true,
            "error" to mapOf("code" to "SCRIPT_ABORTED", "message" to "Script playback was aborted"),
        )

    private fun isAbortResponse(response: Map<String, Any?>): Boolean = response["aborted"] as? Boolean == true

    private suspend fun sleepWithAbortCheck(milliseconds: Int): Boolean {
        val total = maxOf(milliseconds, 0)
        var elapsed = 0
        while (elapsed < total) {
            if (playbackState.isAbortRequested()) return false
            val slice = minOf(50, total - elapsed)
            delay(slice.toLong())
            elapsed += slice
        }
        return !playbackState.isAbortRequested()
    }

    private fun saveScreenshot(
        response: Map<String, Any?>,
        index: Int,
    ): ScriptPlaybackScreenshot? {
        val image = response["image"] as? String ?: return null
        val format = (response["format"] as? String ?: "png").lowercase()
        val extension = if (format == "jpeg") ".jpg" else ".png"
        val cacheDir = ctx.webView?.context?.cacheDir ?: File(System.getProperty("java.io.tmpdir") ?: "/tmp")
        return runCatching {
            val file = File.createTempFile("kelpie-script-$index-", extension, cacheDir)
            file.writeBytes(
                java.util.Base64
                    .getDecoder()
                    .decode(image),
            )
            ScriptPlaybackScreenshot(
                index = index,
                file = file.absolutePath,
                width = intValue(response["width"]),
                height = intValue(response["height"]),
            )
        }.getOrNull()
    }

    private fun errorDetails(response: Map<String, Any?>): Pair<String, String> {
        val error = response["error"] as? Map<*, *> ?: return "SCRIPT_ACTION_FAILED" to "Script action failed"
        return (error["code"] as? String ?: "SCRIPT_ACTION_FAILED") to
            (error["message"] as? String ?: "Script action failed")
    }

    private fun intValue(value: Any?): Int =
        when (value) {
            is Int -> value
            is Double -> value.toInt()
            is Float -> value.toInt()
            else -> 0
        }

    private fun actionList(value: Any?): List<Map<String, Any?>>? {
        val list = value as? List<*> ?: return null
        return list.map { item ->
            val action = item as? Map<*, *> ?: return null
            action.entries.associate { (key, entryValue) ->
                (key as? String ?: return null) to entryValue
            }
        }
    }
}
