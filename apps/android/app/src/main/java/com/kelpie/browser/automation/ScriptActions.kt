package com.kelpie.browser.automation

import android.graphics.Color
import android.webkit.WebView
import com.kelpie.browser.ai.openai.OpenAIJson
import com.kelpie.browser.handlers.HandlerContext
import com.kelpie.browser.network.BrowserGatewaySession
import com.kelpie.browser.network.Router
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeout

/** One typed workflow executor; semantic targeting is the generated fixed reader. */
class ScriptActions(
    private val run: ScriptRun,
    private val ctx: HandlerContext,
    private val router: Router,
    private val view: WebView,
    private val observation: BrowserGatewaySession,
    private val prepareInput: suspend (Int, Double, String) -> Unit,
) {
    private val gateway = checkNotNull(ctx.browserGateway)
    private val overlay = ctx.scriptOverlay

    // One page registry; every action resolves without a token first. The
    // existing retirement lease prevents overlap with an earlier run.
    private val key = "__kelpie_script_android_v1"
    private var pointerX = 20.0
    private var pointerY = 20.0
    var mutationInFlight = false
        private set

    suspend fun guard() {
        if (!run.authority.permits()) stop("SCRIPT_AUTHORIZATION_REVOKED")
        withContext(Dispatchers.Main.immediate) {
            if (!run.authorizedOnMain()) stop("SCRIPT_AUTHORIZATION_REVOKED")
            if (!ctx.scriptForeground) stop("SCRIPT_BACKGROUND")
            if (ctx.tabStore?.activeTabId?.value != run.tabId || ctx.tabStore?.activeTab?.webView !== view) {
                stop("SCRIPT_TAB_CHANGED")
            }
            if (ctx.scriptPlaybackState?.isAbortRequested() == true) stop("SCRIPT_ABORTED")
        }
        if (run.captureExpired()) stop("CAPTURE_DURATION_LIMIT")
        if (run.elapsedMs() > 300_000) stop("SCRIPT_DURATION_LIMIT")
        if (run.stopped.get()) throw ScriptFailure(run.stopReason.get() ?: "SCRIPT_ABORTED", mutationInFlight)
    }

    fun validOnMain(): Boolean =
        run.authorizedOnMain() &&
            ctx.scriptForeground &&
            !run.stopped.get() &&
            ctx.scriptPlaybackState?.isAbortRequested() != true &&
            ctx.tabStore?.activeTabId?.value == run.tabId &&
            ctx.tabStore?.activeTab?.webView === view

    suspend fun pause(milliseconds: Long) {
        val end = System.nanoTime() + milliseconds * 1_000_000
        do {
            guard()
            val remaining = (end - System.nanoTime()) / 1_000_000
            if (remaining > 0) delay(minOf(remaining, 25))
        } while (System.nanoTime() < end)
    }

    suspend fun execute(
        action: Map<String, Any?>,
        index: Int,
    ) {
        guard()
        when (action["action"]) {
            "wait" -> pause(number(action, "ms").toLong())
            "wait-ready" -> ready(action)
            "assert" -> assertion(action)
            "click", "tap", "fill", "type" -> interact(action, index)
            "navigate" -> navigate(action)
            "scroll" ->
                gateway.scriptLease(run.tabId, view, true, ::guard) {
                    overlay.clear()
                    mutationInFlight = true
                    @Suppress("DEPRECATION")
                    val scale = view.scale.toDouble()
                    view.scrollBy((number(action, "deltaX") * scale).toInt(), (number(action, "deltaY") * scale).toInt())
                    guard()
                    mutationInFlight = false
                }
            "commentary" ->
                gateway.scriptLease(run.tabId, view, false, ::guard) {
                    val metrics = ctx.viewportMetrics()
                    overlay.viewport(metrics.viewportWidth.toDouble(), metrics.viewportHeight.toDouble(), document(), preserveExisting = true)
                    overlay.narrate(
                        ScriptOverlay.Commentary(
                            action["text"] as String,
                            System.nanoTime(),
                            number(action, "durationMs"),
                            action["position"] as String,
                        ),
                    )
                }
            "extract" -> run.output(action["name"] as String, read("tab.extract", objectMap(action["params"])))
            "output" -> {
                val method =
                    when (action["source"]) {
                        "url" -> "tab.url"
                        "title" -> "tab.title"
                        else -> "tab.status"
                    }
                run.output(action["name"] as String, read(method))
            }
            "screenshot" -> Unit // The capture coordinator records exactly one step PNG.
            else -> throw ScriptFailure("UNSUPPORTED_SCRIPT_ACTION")
        }
        guard()
    }

    private suspend fun interact(
        action: Map<String, Any?>,
        index: Int,
    ) = gateway.scriptLease(run.tabId, view, true, ::guard) {
        val resolved = resolve(action)
        val x = number(resolved, "x")
        val y = number(resolved, "y")
        val width = number(resolved, "viewportWidth")
        val height = number(resolved, "viewportHeight")
        val token = resolved["token"] as? String ?: throw ScriptFailure("TARGET_EVALUATION_FAILED")
        val edit = action["action"] in setOf("fill", "type")
        val sensitive = action["sensitive"] == true || resolved["sensitive"] == true
        if (sensitive) {
            if (edit) run.redactor.add(action["text"] as String)
            if (run.script["capture"] != null || ScriptPreflight.actions(run.script).any { it["action"] == "screenshot" }) {
                throw ScriptFailure("SENSITIVE_CAPTURE_REFUSED")
            }
        }
        val oldDocument = document()
        val visual = objectMap(resolved["visualViewport"])
        val visualWidth = number(visual, "width")
        val visualHeight = number(visual, "height")
        if (visualWidth <= 0 || visualHeight <= 0 || number(visual, "scale") <= 0) throw ScriptFailure("TARGET_EVALUATION_FAILED")
        overlay.viewport(visualWidth, visualHeight, oldDocument, number(visual, "offsetLeft"), number(visual, "offsetTop"))
        val pointer = objectMap(run.script["pointer"])
        if (pointer["enabled"] == true) {
            val duration = (pointer["durationMs"] as? Number)?.toDouble() ?: 500.0
            overlay.move(
                ScriptOverlay.Pointer(
                    pointerX.coerceIn(0.0, width),
                    pointerY.coerceIn(0.0, height),
                    x,
                    y,
                    System.nanoTime(),
                    duration,
                    pointer["curve"] != "c",
                ),
            )
            pause(duration.toLong())
            resolve(action, token) // Refuse a changed viewport before showing/capturing the tap.
        }
        guard()
        val tap = objectMap(run.script["tapIndicator"])
        val movies = (objectMap(run.script["capture"])["formats"] as? List<*>).orEmpty().any { it == "gif" || it == "video" }
        val marker =
            ScriptOverlay.Tap(
                x,
                y,
                System.nanoTime(),
                (tap["radius"] as? Number)?.toDouble() ?: 20.0,
                (tap["durationMs"] as? Number)?.toDouble() ?: 700.0,
                Color.parseColor(tap["color"] as? String ?: "#3B82F6"),
                tap["wobble"] != false,
                tap["fade"] != false,
                held = movies,
            )
        overlay.indicate(marker)
        prepareInput(index, (marker.start - run.startedNanos) / 1_000_000.0, oldDocument)
        if (movies) overlay.indicate(marker.copy(start = System.nanoTime(), held = false))
        guard()
        // The same object/token/document/geometry is checked atomically after
        // movie admission and synchronous focus/default handlers.
        mutationInFlight = true
        val done = resolve(action, token, dispatch = !edit, edit = edit)
        guard()
        mutationInFlight = false
        pointerX = x
        pointerY = y
        if (done["inputGuarantee"] != "synthetic-coordinate") throw ScriptFailure("TARGET_EVALUATION_FAILED", true)
    }

    private suspend fun navigate(action: Map<String, Any?>) =
        gateway.scriptLease(run.tabId, view, true, ::guard) {
            overlay.clear()
            ctx.tabStore?.activeTab?.isStartPage = false
            val previous = ctx.remoteDocumentGuard
            ctx.remoteDocumentGuard = { previous?.invoke() != false && validOnMain() }
            try {
                mutationInFlight = true
                val result =
                    withTimeout(30_000) {
                        router.handle("navigate", mapOf("url" to action["url"]), bypassRecordingGate = true, fromGateway = true).second
                    }
                if (result["success"] != true) throw ScriptFailure("SCRIPT_NAVIGATION_FAILED", true)
                guard()
                mutationInFlight = false
            } finally {
                ctx.remoteDocumentGuard = previous
            }
        }

    private suspend fun ready(action: Map<String, Any?>) {
        val end = System.nanoTime() + number(action, "timeoutMs").toLong() * 1_000_000
        val params =
            buildMap<String, Any?> {
                put("state", action["state"])
                if (action["selector"] != null) put("selector", action["selector"])
            }
        do {
            val value = objectMap(read("tab.ready", params))
            if ((value["matches"] as? Number)?.toInt()?.let { it > 1 } == true) throw ScriptFailure("AMBIGUOUS_TARGET")
            if (value["incomplete"] == true) throw ScriptFailure("READINESS_QUERY_LIMIT")
            if (value["ready"] == true) return
            if (System.nanoTime() >= end) break
            pause(100)
        } while (true)
        throw ScriptFailure("SCRIPT_READINESS_TIMEOUT")
    }

    private suspend fun assertion(action: Map<String, Any?>) {
        val end = System.nanoTime() + number(action, "timeoutMs").toLong() * 1_000_000
        do {
            guard()
            val result =
                gateway.scriptLease(run.tabId, view, false, ::guard) {
                    rawTarget(action, observe = true)
                }
            val error = result["error"] as? String
            val absent = error == "TARGET_NOT_FOUND" || error == "TARGET_NOT_INTERACTABLE"
            if (error != null && !absent && error != "TARGET_OBSCURED") throw targetFailure(result)
            val matches =
                when (action["state"]) {
                    "hidden" -> absent
                    "enabled" -> result["ok"] == true && result["enabled"] == true
                    else -> result["ok"] == true && result["visible"] == true
                }
            if (matches) return
            if (System.nanoTime() >= end) break
            pause(100)
        } while (true)
        throw ScriptFailure("SCRIPT_ASSERTION_FAILED")
    }

    private suspend fun read(
        method: String,
        params: Map<String, Any?> = emptyMap(),
    ): Any? {
        guard()
        val result = observation.call(mapOf("version" to 1, "method" to method, "tabId" to run.tabId, "params" to params))
        guard()
        if (result?.get("ok") != true) throw ScriptFailure("SCRIPT_OBSERVATION_FAILED")
        return result["value"]
    }

    private suspend fun resolve(
        action: Map<String, Any?>,
        token: String? = null,
        dispatch: Boolean = false,
        edit: Boolean = false,
    ): Map<String, Any?> {
        val result = rawTarget(action, token, dispatch, edit)
        if (result["ok"] != true) {
            if (dispatch || edit) mutationInFlight = result["mayHaveCompleted"] == true
            throw targetFailure(result)
        }
        return result
    }

    private suspend fun rawTarget(
        action: Map<String, Any?>,
        token: String? = null,
        dispatch: Boolean = false,
        edit: Boolean = false,
        observe: Boolean = false,
    ): Map<String, Any?> {
        val options = mutableMapOf<String, Any?>("target" to action["target"], "key" to key)
        if (token != null) options["token"] = token
        if (dispatch) options["dispatch"] = true
        if (observe) options["observe"] = true
        if (edit) options["edit"] = mapOf("action" to action["action"], "text" to action["text"])
        val generated =
            ScriptNative.targetExpression(OpenAIJson.encode(OpenAIJson.fromAny(options)))
                ?: throw ScriptFailure("INVALID_SCRIPT_TARGET")
        val expression =
            OpenAIJson.parseObjectOrNull(generated)?.let(OpenAIJson::toMap)?.get("expression") as? String
                ?: throw ScriptFailure("INVALID_SCRIPT_TARGET")
        return withTimeout(30_000) { ctx.evaluateAutomationJSON(expression, ::validOnMain) }
    }

    private fun targetFailure(result: Map<String, Any?>): ScriptFailure {
        val requested = result["error"] as? String
        val safe =
            setOf(
                "INVALID_TARGET_OPERATION",
                "STALE_TARGET",
                "TARGET_OUTSIDE_VIEWPORT",
                "AMBIGUOUS_TARGET",
                "INVALID_TARGET",
                "TARGET_QUERY_LIMIT",
                "TARGET_NOT_FOUND",
                "TARGET_NOT_INTERACTABLE",
                "VIEWPORT_CHANGED",
                "TARGET_MOVED",
                "TARGET_OBSCURED",
                "TARGET_NOT_EDITABLE",
                "INPUT_UNCERTAIN",
            )
        return ScriptFailure(requested?.takeIf { it in safe } ?: "TARGET_EVALUATION_FAILED", result["mayHaveCompleted"] == true)
    }

    fun document(): String = ctx.tabStore?.activeTab?.documentVersion ?: throw ScriptFailure("SCRIPT_TAB_CHANGED")

    private fun stop(code: String): Nothing {
        run.stop(code)
        throw ScriptFailure(code, mutationInFlight)
    }

    private fun number(
        value: Map<String, Any?>,
        field: String,
    ): Double = (value[field] as? Number)?.toDouble()?.takeIf { it.isFinite() } ?: throw ScriptFailure("INVALID_SCRIPT")

    @Suppress("UNCHECKED_CAST")
    private fun objectMap(value: Any?): Map<String, Any?> = value as? Map<String, Any?> ?: emptyMap()
}
