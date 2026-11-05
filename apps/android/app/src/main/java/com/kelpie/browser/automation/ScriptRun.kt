package com.kelpie.browser.automation

import com.kelpie.browser.ai.openai.OpenAIJson
import java.io.File
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicReference

/** One immutable owner and pinned tab. Neither IDs nor page data confer authority. */
class ScriptRun(
    val id: String,
    authority: ScriptAuthority,
    val tabId: String,
    script: Map<String, Any?>,
    directory: File,
    val startedNanos: Long = System.nanoTime(),
    val createdAtMs: Long = System.currentTimeMillis(),
) {
    val owner = authority.owner

    @Volatile private var activeAuthority: ScriptAuthority? = authority

    @Volatile private var workflow = script
    val authority: ScriptAuthority get() = activeAuthority ?: throw ScriptFailure("SCRIPT_FINISHED")
    val script: Map<String, Any?> get() = workflow
    private val totalActions = ScriptPreflight.actions(script).size
    private var extractionNames = ScriptPreflight.actions(script).filter { it["action"] == "extract" }.map { it["name"] as String }
    private var outputBytes = 0L
    val artifacts = ScriptArtifacts(directory)
    val redactor = ScriptRedactor()

    @Volatile private var captureDeadlineMs: Double? = null
    val discardCapture = AtomicBoolean()
    val stopped = AtomicBoolean()
    val stopReason = AtomicReference<String?>(null)
    private var phase = "running"
    private var error: String? = null
    private var uncertain = false
    private var currentIndex: Int? = null
    private var currentName: String? = null
    private var executed = 0
    private var endedMs: Long? = null
    private val outputs = linkedMapOf<String, Any?>()

    fun stop(code: String) {
        if (code in setOf("SENSITIVE_CAPTURE_REFUSED", "OUTPUT_REDACTION_FAILED")) discardCapture.set(true)
        stopReason.compareAndSet(null, code)
        stopped.set(true)
    }

    fun startCapture(
        absoluteMs: Double,
        maxDurationMs: Long,
    ) {
        captureDeadlineMs = absoluteMs + maxDurationMs
    }

    fun captureExpired(): Boolean = captureDeadlineMs?.let { (System.nanoTime() - startedNanos) / 1_000_000.0 >= it } == true

    fun elapsedMs(): Long = (System.nanoTime() - startedNanos) / 1_000_000

    fun authorizedOnMain(): Boolean = activeAuthority?.permitsOnMain() == true

    @Synchronized
    fun clearPrivate() {
        workflow = emptyMap()
        extractionNames = emptyList()
        outputs.clear()
        redactor.clear()
        activeAuthority = null
        captureDeadlineMs = null
    }

    @Synchronized
    fun active(): Boolean = phase == "running" || phase == "finalizing"

    @Synchronized
    fun step(
        index: Int,
        name: String,
    ) {
        currentIndex = index
        currentName = name
    }

    @Synchronized
    fun succeeded() {
        executed++
    }

    @Synchronized
    fun output(
        name: String,
        value: Any?,
    ) {
        val bytes = OpenAIJson.encode(OpenAIJson.fromAny(value)).toByteArray(Charsets.UTF_8).size
        if (outputBytes + bytes > 262_144) throw ScriptFailure("SCRIPT_OUTPUT_LIMIT")
        val candidate = outputs + (name to value)
        redactor.redact(candidate, extractionNames) // Bound/project before subsequent actions.
        outputBytes += bytes
        outputs[name] = value
    }

    @Synchronized
    fun finalizing() {
        phase = "finalizing"
    }

    @Synchronized
    fun finish(
        code: String?,
        mayHaveCompleted: Boolean,
    ) {
        val firstCode = error ?: code ?: stopReason.get()
        error = firstCode
        uncertain = uncertain || mayHaveCompleted
        phase =
            if (firstCode == "SCRIPT_ABORTED" || firstCode == "SCRIPT_BACKGROUND") {
                "aborted"
            } else if (firstCode != null) {
                "failed"
            } else {
                "completed"
            }
        endedMs = elapsedMs()
        if (discardCapture.get()) artifacts.deleteOwned() else artifacts.discardUnregistered()
    }

    @Synchronized
    fun prepareOutputs(): Map<String, Any?> = redactor.redact(outputs.toMap(), extractionNames)

    /** Metadata-only queries never materialize or retain page-derived output bodies. */
    @Synchronized
    fun status(
        includeOutputs: Boolean = false,
        preparedOutputs: Map<String, Any?> = emptyMap(),
    ): Map<String, Any?> =
        buildMap {
            put("success", if (includeOutputs) phase == "completed" else true)
            put("supportedVersions", listOf(1))
            put("inputGuarantee", "synthetic-coordinate")
            put("runId", id)
            put("playing", active())
            put("state", phase)
            currentIndex?.let { put("actionIndex", it) }
            put("totalActions", totalActions)
            put("elapsedMs", endedMs ?: elapsedMs())
            endedMs?.let { put("totalDurationMs", it) }
            put("abortRequested", stopped.get())
            put("artifacts", artifacts.manifests(phase != "completed"))
            if (!active()) put("runSuccess", phase == "completed")
            if (error != null) put(if (includeOutputs) "error" else "runError", mapOf("code" to error, "message" to "Script stopped"))
            if (uncertain) put("mayHaveCompleted", true)
            if (includeOutputs) {
                put("tabId", tabId)
                put("actionsExecuted", executed)
                put("currentActionName", currentName)
                put("aborted", phase == "aborted")
                put("partial", phase != "completed")
                put("outputs", preparedOutputs)
            }
        }
}
