package com.kelpie.browser.automation

import android.content.Context
import android.webkit.WebView
import com.kelpie.browser.ai.openai.OpenAIJson
import com.kelpie.browser.handlers.HandlerContext
import com.kelpie.browser.handlers.ScriptPlaybackState
import com.kelpie.browser.network.BrowserGatewaySession
import com.kelpie.browser.network.Router
import com.kelpie.browser.network.errorResponse
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeout
import java.io.File
import kotlin.coroutines.resume

/** Strict opt-in v1 routes beside the existing legacy handler, under existing grants. */
class ScriptRuntime(
    context: Context,
    private val ctx: HandlerContext,
    private val router: Router,
    private val playback: ScriptPlaybackState,
) {
    private val store = ScriptRunStore(File(context.cacheDir, "script-runs"))
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)

    @Volatile private var legacyOwner: ScriptOwner? = null

    suspend fun play(
        body: Map<String, Any?>,
        legacy: suspend () -> Map<String, Any?>,
    ): Map<String, Any?> =
        safe {
            val authority = currentScriptAuthority()
            if (!body.containsKey("version")) {
                return@safe checkNotNull(ctx.browserGateway).legacy("play-script") {
                    legacyOwner = authority.owner
                    try {
                        legacy()
                    } finally {
                        legacyOwner = null
                    }
                }
            }
            val validated =
                OpenAIJson
                    .parseObjectOrNull(
                        ScriptNative.validate(OpenAIJson.encode(OpenAIJson.fromAny(body))),
                    )?.let(OpenAIJson::toMap) ?: throw ScriptFailure("INVALID_SCRIPT")
            if (validated["valid"] != true) throw ScriptFailure("INVALID_SCRIPT")
            val script = ScriptPreflight.admit(objectMap(validated["script"]))
            val capture = objectMap(script["capture"])
            if ("video" in (capture["formats"] as? List<*>).orEmpty() && !runCatching { ScriptVideoEncoder.available() }.getOrDefault(false)) {
                throw ScriptFailure("CAPTURE_VIDEO_UNAVAILABLE")
            }
            val view =
                withContext(Dispatchers.Main.immediate) {
                    if (!ctx.scriptForeground) throw ScriptFailure("SCRIPT_BACKGROUND")
                    if (ctx.isIn3DInspector) throw ScriptFailure("SCRIPT_BROWSER_BUSY")
                    ctx.tabStore
                        ?.activeTab
                        ?.takeIf { it.id == script["tabId"] }
                        ?.webView
                        ?: throw ScriptFailure("SCRIPT_TAB_CHANGED")
                }
            // Wait for the existing retirement lease before admitting a new run.
            withTimeout(30_000) {
                checkNotNull(ctx.browserGateway).scriptLease(script["tabId"] as String, view, false, { authority.requireCurrent() }) { Unit }
            }
            if (!playback.start(ScriptPreflight.actions(script).size, false)) throw ScriptFailure("RECORDING_IN_PROGRESS")
            val run =
                try {
                    store.start(authority, script)
                } catch (error: Exception) {
                    playback.finishFatalFailure("SCRIPT_ADMISSION_FAILED", "Script admission failed")
                    throw error
                }
            for (action in ScriptPreflight.actions(script)) {
                if (action["sensitive"] == true) (action["text"] as? String)?.let(run.redactor::add)
            }
            val result = CompletableDeferred<Map<String, Any?>>()
            scope.launch(authority) { execute(run, view, result) }
            val response = result.await()
            authority.requireCurrent()
            response
        }

    suspend fun status(
        body: Map<String, Any?>,
        legacy: () -> Map<String, Any?>,
    ): Map<String, Any?> =
        safe {
            val authority = currentScriptAuthority()
            controlBody(body)
            val legacyActive = body["runId"] == null && legacyOwner == authority.owner
            val run = if (legacyActive) null else store.owned(authority.owner, body["runId"] as? String)
            val value =
                when {
                    run != null -> metadata(run)
                    legacyActive -> legacy()
                    else -> mapOf("success" to true, "supportedVersions" to listOf(1), "playing" to false, "state" to "idle", "inputGuarantee" to "synthetic-coordinate")
                }
            authority.requireCurrent()
            value
        }

    suspend fun abort(
        body: Map<String, Any?>,
        legacy: () -> Map<String, Any?>,
    ): Map<String, Any?> =
        safe {
            val authority = currentScriptAuthority()
            controlBody(body)
            if (body["runId"] == null && legacyOwner == authority.owner) return@safe legacy()
            val run = store.owned(authority.owner, body["runId"] as? String)
            if (run == null) {
                if (store.active() || legacyOwner != null) throw ScriptFailure("SCRIPT_NOT_FOUND")
                return@safe legacy()
            }
            if (run.active()) run.stop("SCRIPT_ABORTED")
            authority.requireCurrent()
            metadata(run)
        }

    suspend fun artifact(body: Map<String, Any?>): Map<String, Any?> =
        safe {
            val authority = currentScriptAuthority()
            val id = body["runId"] as? String ?: throw ScriptFailure("INVALID_PARAMS")
            val run = store.owned(authority.owner, id) ?: throw ScriptFailure("SCRIPT_NOT_FOUND")
            val result = withContext(Dispatchers.IO) { run.artifacts.read(run.id, body) }
            authority.requireCurrent()
            result
        }

    fun stop() {
        store.stopActive()
    }

    fun close() {
        stop()
        scope.cancel()
    }

    fun capabilities(): Map<String, Any?> =
        mapOf(
            "supportedVersions" to listOf(1),
            "inputGuarantee" to "synthetic-coordinate",
            "supportedActions" to ScriptPreflight.supportedActions.toList().sorted(),
            "captureFormats" to (
                listOf("gif", "screenshots") +
                    if (runCatching { ScriptVideoEncoder.available() }.getOrDefault(false)) listOf("video") else emptyList()
            ),
            "nativeSessions" to false,
            "webMcp" to mapOf("available" to false, "reason" to "No registered real API and explicit host grant"),
            "lightpanda" to mapOf("available" to false, "reason" to "Desktop orchestration backend"),
        )

    private suspend fun execute(
        run: ScriptRun,
        view: WebView,
        result: CompletableDeferred<Map<String, Any?>>,
    ) {
        var observer: BrowserGatewaySession? = null
        var actions: ScriptActions? = null
        var capture: ScriptCapture? = null
        var failure: ScriptFailure? = null
        var watchdog: kotlinx.coroutines.Job? = null
        try {
            lateinit var runner: ScriptActions
            observer =
                checkNotNull(ctx.browserGateway).scriptObservationSession(run.tabId, view) {
                    try {
                        runner.guard()
                        true
                    } catch (_: Exception) {
                        false
                    }
                }
            runner =
                ScriptActions(run, ctx, router, view, checkNotNull(observer)) { index, markerMs, documentId ->
                    capture?.holdMarker(markerMs, documentId)
                    capture?.step(index)
                }
            actions = runner
            runner.guard()
            watchdog =
                scope.launch {
                    while (run.active()) {
                        if (!run.authority.permits()) run.stop("SCRIPT_AUTHORIZATION_REVOKED")
                        delay(100)
                    }
                }
            settleLayout(view)
            val settings =
                objectMap(run.script["capture"]).ifEmpty {
                    mapOf(
                        "formats" to emptyList<String>(),
                        "fps" to 15,
                        "maxWidth" to 1280,
                        "maxDurationMs" to 300_000,
                        "maxBytes" to 67_108_864,
                    )
                }
            if (run.script["capture"] != null || ScriptPreflight.actions(run.script).any { it["action"] == "screenshot" }) {
                capture = ScriptCapture(run, view, ctx.scriptOverlay, settings, runner::document, runner::guard)
                capture.start(CoroutineScope(kotlin.coroutines.coroutineContext))
            }
            val steps = ScriptPreflight.actions(run.script)
            for ((index, action) in steps.withIndex()) {
                runner.guard()
                run.step(index, action["action"] as String)
                runner.execute(action, index)
                if (action["action"] !in setOf("click", "tap", "fill", "type")) {
                    capture?.step(index, action["action"] == "screenshot")
                }
                runner.guard()
                run.succeeded()
                if (index < steps.lastIndex) {
                    runner.pause((run.script["defaultWaitBetweenActions"] as? Number)?.toLong() ?: 0)
                }
            }
        } catch (error: ScriptFailure) {
            failure = error
        } catch (_: CancellationException) {
            failure = ScriptFailure("SCRIPT_ABORTED", actions?.mutationInFlight == true)
        } catch (_: Exception) {
            failure =
                ScriptFailure(
                    if (actions?.mutationInFlight == true) "INPUT_UNCERTAIN" else "SCRIPT_FAILED",
                    actions?.mutationInFlight == true,
                )
        } finally {
            withContext(NonCancellable) {
                failure?.let { run.stop(it.code) }
                run.finalizing()
                watchdog?.cancel()
                try {
                    capture?.finish()
                } catch (_: Exception) {
                    if (failure == null) failure = ScriptFailure("CAPTURE_ENCODING_FAILED")
                }
                // Retirement belongs to the original renderer callback. Status
                // and Stop remain live while that callback drains; never replay.
                try {
                    observer?.close()
                } catch (_: Exception) {
                    if (failure == null) failure = ScriptFailure("SCRIPT_RETIREMENT_FAILED")
                }
                val stopped = run.stopReason.get()
                if (failure == null && stopped != null) failure = ScriptFailure(stopped)
                withContext(Dispatchers.Main.immediate) { ctx.scriptOverlay.clear() }
                val code = failure?.code
                val aborted = code == "SCRIPT_ABORTED" || code == "SCRIPT_BACKGROUND"
                run.finish(code, aborted, failure?.mayHaveCompleted == true || actions?.mutationInFlight == true)
                if (aborted) {
                    playback.finishAborted()
                } else if (code != null) {
                    playback.finishFatalFailure(code, "Script stopped")
                } else {
                    playback.finishSuccess()
                }
                val response =
                    try {
                        run.status(includeOutputs = true)
                    } catch (_: Exception) {
                        run.finish("SCRIPT_OUTPUT_REDACTION_FAILED", false, false)
                        run.status() + errorResponse("SCRIPT_OUTPUT_REDACTION_FAILED", "Script output unavailable")
                    }
                run.clearPrivate()
                result.complete(response)

                store.retire()
            }
        }
    }

    private suspend fun settleLayout(view: WebView) =
        withContext(Dispatchers.Main.immediate) {
            suspendCancellableCoroutine<Unit> { continuation ->
                view.postOnAnimation {
                    view.postOnAnimation { if (continuation.isActive) continuation.resume(Unit) }
                }
            }
        }

    private suspend fun safe(action: suspend () -> Map<String, Any?>): Map<String, Any?> =
        try {
            action()
        } catch (error: ScriptFailure) {
            errorResponse(error.code, "Script request refused") +
                if (error.mayHaveCompleted) mapOf("mayHaveCompleted" to true) else emptyMap()
        } catch (_: Exception) {
            errorResponse("SCRIPT_REQUEST_FAILED", "Script request failed")
        }

    private fun metadata(run: ScriptRun): Map<String, Any?> = run.status()

    private fun controlBody(body: Map<String, Any?>) {
        if (body.keys.any { it != "runId" } || (body.containsKey("runId") && body["runId"] !is String)) {
            throw ScriptFailure("INVALID_PARAMS")
        }
    }

    @Suppress("UNCHECKED_CAST")
    private fun objectMap(value: Any?): Map<String, Any?> = value as? Map<String, Any?> ?: emptyMap()
}
