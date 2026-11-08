package com.kelpie.browser.handlers

import com.kelpie.browser.network.errorResponse
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import java.util.concurrent.locks.ReentrantLock
import kotlin.concurrent.withLock

data class ScriptPlaybackIssue(
    val index: Int,
    val action: String,
    val code: String,
    val message: String,
    val skipped: Boolean,
) {
    fun toMap(): Map<String, Any?> =
        buildMap {
            put("index", index)
            put("action", action)
            put("error", mapOf("code" to code, "message" to message))
            if (skipped) put("skipped", true)
        }
}

data class ScriptPlaybackScreenshot(
    val index: Int,
    val file: String,
    val width: Int,
    val height: Int,
) {
    fun toMap(): Map<String, Any?> =
        mapOf(
            "index" to index,
            "file" to file,
            "width" to width,
            "height" to height,
        )
}

class ScriptPlaybackState {
    private data class Session(
        val totalActions: Int,
        val continueOnError: Boolean,
        val startedAtMs: Long,
        var currentActionIndex: Int? = null,
        var currentActionName: String? = null,
        var actionsExecuted: Int = 0,
        var actionsSucceeded: Int = 0,
        var abortRequested: Boolean = false,
        val issues: MutableList<ScriptPlaybackIssue> = mutableListOf(),
        val screenshots: MutableList<ScriptPlaybackScreenshot> = mutableListOf(),
    )

    private val lock = ReentrantLock()
    private var session: Session? = null
    private val _isRecording = MutableStateFlow(false)
    val isRecording: StateFlow<Boolean> = _isRecording.asStateFlow()

    fun start(
        totalActions: Int,
        continueOnError: Boolean,
    ): Boolean =
        lock.withLock {
            if (session != null) return false
            session =
                Session(
                    totalActions = totalActions,
                    continueOnError = continueOnError,
                    startedAtMs = System.currentTimeMillis(),
                )
            _isRecording.value = true
            true
        }

    fun updateCurrentAction(
        index: Int,
        action: String,
    ) {
        lock.withLock {
            val active = session ?: return
            active.currentActionIndex = index
            active.currentActionName = action
        }
    }

    fun recordSuccess(index: Int) {
        lock.withLock {
            val active = session ?: return
            active.actionsExecuted = maxOf(active.actionsExecuted, index + 1)
            active.actionsSucceeded += 1
        }
    }

    fun recordFailure(
        index: Int,
        action: String,
        code: String,
        message: String,
        skipped: Boolean,
    ) {
        lock.withLock {
            val active = session ?: return
            active.actionsExecuted = maxOf(active.actionsExecuted, index + 1)
            active.issues += ScriptPlaybackIssue(index, action, code, message, skipped)
        }
    }

    fun addScreenshot(
        index: Int,
        file: String,
        width: Int,
        height: Int,
    ) {
        lock.withLock {
            val active = session ?: return
            active.screenshots += ScriptPlaybackScreenshot(index, file, width, height)
        }
    }

    fun isAbortRequested(): Boolean = lock.withLock { session?.abortRequested ?: false }

    fun requestAbort(): Map<String, Any?>? =
        lock.withLock {
            val active = session ?: return null
            active.abortRequested = true
            buildResult(success = false, aborted = true, session = active, topLevelError = null)
        }

    fun finishSuccess(): Map<String, Any?> =
        lock.withLock {
            val active = session ?: return mapOf("success" to true)
            session = null
            _isRecording.value = false
            if (active.issues.isNotEmpty()) {
                val count = active.issues.size
                return buildResult(
                    success = false,
                    aborted = false,
                    session = active,
                    topLevelError = "SCRIPT_PARTIAL_FAILURE" to "$count of ${active.totalActions} actions failed",
                )
            }
            buildResult(success = true, aborted = false, session = active, topLevelError = null)
        }

    fun finishFatalFailure(
        code: String,
        message: String,
    ): Map<String, Any?> =
        lock.withLock {
            val active = session ?: return@withLock errorResponse(code, message)
            session = null
            _isRecording.value = false
            buildResult(
                success = false,
                aborted = false,
                session = active,
                topLevelError = code to message,
            )
        }

    fun finishAborted(): Map<String, Any?> =
        lock.withLock {
            val active = session ?: return mapOf("success" to false, "aborted" to true)
            session = null
            _isRecording.value = false
            buildResult(success = false, aborted = true, session = active, topLevelError = null)
        }

    fun statusResponse(): Map<String, Any?> =
        lock.withLock {
            val active = session ?: return mapOf("playing" to false)
            mapOf(
                "playing" to true,
                "currentAction" to active.currentActionIndex,
                "currentActionName" to active.currentActionName,
                "totalActions" to active.totalActions,
                "elapsedMs" to elapsedMilliseconds(active.startedAtMs),
                "abortRequested" to active.abortRequested,
            )
        }

    fun recordingError(method: String): Map<String, Any?>? =
        lock.withLock {
            if (session == null) {
                return@withLock null
            }
            if (method == "abort-script" || method == "get-script-status") {
                return@withLock null
            }
            return@withLock errorResponse("RECORDING_IN_PROGRESS", "Script is playing. Call abort-script to stop.")
        }

    private fun buildResult(
        success: Boolean,
        aborted: Boolean,
        session: Session,
        topLevelError: Pair<String, String>?,
    ): Map<String, Any?> =
        buildMap {
            put("success", success)
            put("actionsExecuted", session.actionsExecuted)
            put("totalDurationMs", elapsedMilliseconds(session.startedAtMs))
            put("errors", session.issues.map { it.toMap() })
            put("screenshots", session.screenshots.map { it.toMap() })
            if (session.continueOnError) {
                put("actionsSucceeded", session.actionsSucceeded)
            }
            if (aborted) {
                put("aborted", true)
            }
            if (topLevelError != null) {
                put("error", mapOf("code" to topLevelError.first, "message" to topLevelError.second))
            }
        }

    private fun elapsedMilliseconds(startedAtMs: Long): Long = System.currentTimeMillis() - startedAtMs
}
