package com.kelpie.browser.automation

import android.content.Context
import android.os.Build
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
import kotlinx.coroutines.TimeoutCancellationException
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
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q &&
                (script["capture"] != null || ScriptPreflight.actions(script).any { it["action"] == "screenshot" })
            ) {
                throw ScriptFailure("CAPTURE_VIEW_UNAVAILABLE")
            }
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
            val started =
                withContext(Dispatchers.Main.immediate) {
                    if (playback.start(ScriptPreflight.actions(script).size, false)) {
                        ctx.scriptOverlay.clear()
                        true
                    } else {
                        false
                    }
                }
            if (!started) throw ScriptFailure("RECORDING_IN_PROGRESS")
            val run =
                try {
                    store.start(authority, script)
                } catch (error: Exception) {
                    playback.finishFatalFailure("SCRIPT_ADMISSION_FAILED", "Script admission failed")
                    throw error
                }
            withContext(Dispatchers.Main.immediate) { ctx.scriptOverlay.claimRun(run.id) }
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
            ctx.scriptOverlay.clearRetainedOwner(run.id)
            if (run.active()) run.stop("SCRIPT_ABORTED")
            authority.requireCurrent()
            metadata(run)
        }

    suspend fun artifact(body: Map<String, Any?>): Map<String, Any?> =
        safe {
            val authority = currentScriptAuthority()
            val id = body["runId"] as? String ?: throw ScriptFailure("INVALID_PARAMS")
            val run =
                try {
                    store.owned(authority.owner, id) ?: throw ScriptFailure("ARTIFACT_NOT_FOUND")
                } catch (failure: ScriptFailure) {
                    if (failure.code == "SCRIPT_NOT_FOUND") throw ScriptFailure("ARTIFACT_NOT_FOUND")
                    throw failure
                }
            val result = withContext(Dispatchers.IO) { run.readArtifact(body) }
            authority.requireCurrent()
            result
        }

    fun stop() {
        ctx.scriptOverlay.clear()
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
                if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
                    emptyList()
                } else {
                    listOf("gif", "screenshots") +
                        if (runCatching { ScriptVideoEncoder.available() }.getOrDefault(false)) listOf("video") else emptyList()
                }
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
            if (run.script["capture"] != null || ScriptPreflight.actions(run.script).any { it["action"] == "screenshot" }) {
                try {
                    withTimeout(5_000) {
                        while (!ctx.scriptCaptureScene) {
                            runner.guard()
                            delay(16)
                        }
                    }
                } catch (_: TimeoutCancellationException) {
                    throw ScriptFailure("CAPTURE_VIEW_UNAVAILABLE")
                }
            }
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
                capture =
                    ScriptCapture(run, view, {
                        if (ctx.scriptCaptureScene &&
                            !ctx.scriptCaptureActionMode &&
                            !ctx.isIn3DInspector &&
                            ctx.activePanel.value == null
                        ) {
                            ctx.scriptCaptureSceneGeneration
                        } else {
                            -1L
                        }
                    }, settings, runner::document, runner::guard)
                capture.start(CoroutineScope(kotlin.coroutines.coroutineContext))
            }
            val steps = ScriptPreflight.actions(run.script)
            for ((index, action) in steps.withIndex()) {
                runner.guard()
                run.step(index, action["action"] as String)
                runner.execute(action, index)
                val emptyPacedType = (action["__pacedPlan"] as? ScriptPacedPlan)?.let { !it.clearFirst && it.scalars.isEmpty() } == true
                if (action["action"] !in setOf("click", "tap", "fill", "type") || emptyPacedType) {
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
                val movies = (objectMap(run.script["capture"])["formats"] as? List<*>).orEmpty().any { it == "gif" || it == "video" }
                if (failure != null || run.stopReason.get() != null || movies) {
                    withContext(Dispatchers.Main.immediate) { ctx.scriptOverlay.clearOwned(run.id) }
                }
                val safeOutputs =
                    try {
                        run.prepareOutputs()
                    } catch (_: Exception) {
                        run.stop("OUTPUT_REDACTION_FAILED")
                        if (failure == null) failure = ScriptFailure("OUTPUT_REDACTION_FAILED")
                        null
                    }
                val stopped = run.stopReason.get()
                if (failure == null && stopped != null) failure = ScriptFailure(stopped)
                val code = failure?.code
                run.finish(code, failure?.mayHaveCompleted == true || actions?.mutationInFlight == true)
                val response =
                    if (safeOutputs != null) {
                        run.status(includeOutputs = true, preparedOutputs = safeOutputs)
                    } else {
                        run.status() + errorResponse(code ?: "OUTPUT_REDACTION_FAILED", "Script output unavailable")
                    }
                val terminal = run.status()
                val terminalError = (terminal["runError"] as? Map<*, *>)?.get("code") as? String
                if (terminal["state"] == "aborted") {
                    playback.finishAborted()
                } else if (terminalError != null) {
                    playback.finishFatalFailure(terminalError, "Script stopped")
                } else {
                    playback.finishSuccess()
                }
                if (terminal["state"] == "completed" && terminalError == null && !movies) {
                    val authority = run.authority
                    withContext(Dispatchers.Main.immediate) {
                        val overlay = ctx.scriptOverlay
                        val windowToken = view.windowToken
                        val root = view.rootView
                        val expectedDocument = ctx.tabStore?.activeTab?.documentVersion
                        val valid: () -> Boolean = {
                            val active = ctx.tabStore?.activeTab
                            ctx.scriptForeground &&
                                active != null &&
                                active.id == run.tabId &&
                                active.webView === view &&
                                active.documentVersion == expectedDocument &&
                                ctx.scriptPlaybackState?.isRecording?.value != true &&
                                view.isAttachedToWindow &&
                                view.isShown &&
                                view.hasWindowFocus() &&
                                view.rootView === root &&
                                view.windowToken === windowToken &&
                                runCatching { authority.permitsOnMain() }.getOrDefault(false)
                        }
                        val retained =
                            if (windowToken != null && expectedDocument != null) {
                                overlay.retainFinalTap(run.id, System.nanoTime(), valid)
                            } else {
                                null
                            }
                        if (retained != null && retained.document == expectedDocument && windowToken != null) {
                            ScriptOverlayRetirement.start(overlay, retained, authority, ctx, run.tabId, view, root, windowToken)
                        } else {
                            overlay.clearOwned(run.id)
                        }
                    }
                } else {
                    withContext(Dispatchers.Main.immediate) { ctx.scriptOverlay.clearOwned(run.id) }
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
