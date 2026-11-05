package com.kelpie.browser.automation

import android.graphics.Bitmap
import android.graphics.Color
import android.webkit.WebView
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.asCoroutineDispatcher
import kotlinx.coroutines.cancelAndJoin
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.FileOutputStream
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicInteger

/** Bounded continuous native frames. One queued command; no unbounded bitmap backlog. */
class ScriptCapture(
    private val run: ScriptRun,
    private val view: WebView,
    private val scene: () -> Long,
    private val options: Map<String, Any?>,
    private val document: () -> String,
    private val guard: suspend () -> Unit,
) {
    private data class Frame(
        val bitmap: Bitmap,
        val elapsedMs: Double,
        val documentId: String,
    )

    private sealed interface Command {
        data class Sample(
            val frame: Frame,
            val step: Int?,
            val ack: CompletableDeferred<Unit>?,
        ) : Command

        data class Finish(
            val terminalMs: Double,
            val done: CompletableDeferred<Unit>,
        ) : Command
    }

    private val diagnostics = ScriptCaptureDiagnostics()
    private val compositor = ScriptCompositorCapture(view, scene, diagnostics)
    private val snapshotMutex = Mutex()
    private val dispatcher = Executors.newSingleThreadExecutor { Thread(it, "KelpieCapture") }.asCoroutineDispatcher()
    private val channel = Channel<Command>(1)
    private val formats = (options["formats"] as? List<*>)?.filterIsInstance<String>().orEmpty()
    private val admission = ScriptMovieAdmission(formats)
    private val fps = (options["fps"] as? Number)?.toInt() ?: 15
    private val budget = ScriptMediaBudget((options["maxBytes"] as? Number)?.toLong() ?: 67_108_864)
    private val dropped = AtomicInteger()
    private var sampler: Job? = null
    private var worker: Job? = null
    private var initialWidth = 0
    private var initialHeight = 0
    private var initialScale = 0f
    private var outputWidth = 0
    private var outputHeight = 0
    private var finished = false

    @Volatile private var originMs = 0.0

    suspend fun start(scope: CoroutineScope) {
        withContext(kotlinx.coroutines.Dispatchers.Main.immediate) {
            initialWidth = view.width
            initialHeight = view.height
            @Suppress("DEPRECATION")
            val scale = view.scale
            initialScale = scale
            if (initialWidth <= 0 || initialHeight <= 0 || initialScale <= 0) throw ScriptFailure("CAPTURE_VIEW_UNAVAILABLE")
            val limit = (options["maxWidth"] as? Number)?.toInt() ?: 1280
            outputWidth = minOf(initialWidth, limit)
            outputHeight = (initialHeight.toLong() * outputWidth / initialWidth).toInt()
            if ("video" in formats) {
                outputWidth = outputWidth and -2
                outputHeight = outputHeight and -2
            }
            if (outputWidth < 2 ||
                outputHeight < 2 ||
                outputHeight > 4096 ||
                outputWidth.toLong() * outputHeight > 8_388_608
            ) {
                throw ScriptFailure("CAPTURE_INVALID_SIZE")
            }
        }
        worker = CoroutineScope(NonCancellable + dispatcher).launch { encode() }
        val first = CompletableDeferred<Unit>()
        channel.send(Command.Sample(snapshot(), null, first))
        first.await()
        if (formats.any { it == "gif" || it == "video" }) {
            sampler =
                scope.launch {
                    val period = 1_000_000_000L / fps
                    var next = System.nanoTime() + period
                    while (!run.stopped.get()) {
                        val wait = next - System.nanoTime()
                        if (wait > 0) delay((wait / 1_000_000).coerceAtLeast(1))
                        val elapsed = run.elapsedMs() - originMs
                        val max = (options["maxDurationMs"] as? Number)?.toLong() ?: 60_000
                        if (elapsed >= max) {
                            run.stop("CAPTURE_DURATION_LIMIT")
                            break
                        }
                        try {
                            val frame = snapshot()
                            if (!channel.trySend(Command.Sample(frame, null, null)).isSuccess) {
                                frame.bitmap.recycle()
                                dropped.incrementAndGet()
                            }
                        } catch (failure: ScriptFailure) {
                            if (failure.code == "SCRIPT_DOCUMENT_CHANGED" && !run.stopped.get()) {
                                // The fenced frame belongs to a retired document.
                                // Drop it; a later sample captures the new one.
                                dropped.incrementAndGet()
                            } else {
                                run.stop(failure.code)
                                break
                            }
                        } catch (cancelled: CancellationException) {
                            diagnostics.failure(ScriptCaptureDiagnostics.Failure.SAMPLER_CANCELLED)
                            throw cancelled
                        } catch (_: Exception) {
                            diagnostics.failure(ScriptCaptureDiagnostics.Failure.SAMPLER_EXCEPTION)
                            run.stop("CAPTURE_FAILED")
                            break
                        }
                        next += period
                        val lag = System.nanoTime() - next
                        if (lag >= 0) {
                            dropped.addAndGet((lag / period + 1).toInt())
                            next = System.nanoTime() + period
                        }
                    }
                }
        }
    }

    /** Hold phase zero until every movie contains the old-document frame. */
    suspend fun holdMarker(
        absoluteMs: Double,
        documentId: String,
    ) {
        if (!admission.enabled()) return
        while (!admission.contains(absoluteMs, documentId)) {
            guard()
            withContext(kotlinx.coroutines.Dispatchers.Main.immediate) {
                if (document() != documentId) throw ScriptFailure("SCRIPT_DOCUMENT_CHANGED")
            }
            delay(10)
        }
        // Measured from acknowledged encoding, never from a queued/dropped frame.
        val end = System.nanoTime() + 1_000_000_000L / fps
        while (System.nanoTime() < end) {
            guard()
            withContext(kotlinx.coroutines.Dispatchers.Main.immediate) {
                if (document() != documentId) throw ScriptFailure("SCRIPT_DOCUMENT_CHANGED")
            }
            delay(10)
        }
    }

    suspend fun step(
        index: Int,
        explicit: Boolean = false,
    ) {
        if (!explicit && "screenshots" !in formats) return
        val ack = CompletableDeferred<Unit>()
        channel.send(Command.Sample(snapshot(), index, ack))
        ack.await()
    }

    suspend fun finish() {
        if (finished) return
        finished = true
        if (worker == null) {
            channel.close()
            dispatcher.close()
            return
        }
        withContext(NonCancellable) {
            sampler?.cancelAndJoin()
            val done = CompletableDeferred<Unit>()
            channel.send(Command.Finish(run.elapsedMs().toDouble(), done))
            done.await()
            worker?.join()
            diagnostics.report()
            channel.close()
            dispatcher.close()
        }
    }

    private suspend fun snapshot(): Frame =
        snapshotMutex.withLock {
            guard()
            withContext(kotlinx.coroutines.Dispatchers.Main.immediate) {
                withCaptureDeadline(5_000, { diagnostics.failure(ScriptCaptureDiagnostics.Failure.SNAPSHOT_TIMEOUT) }) {
                    guard()
                    @Suppress("DEPRECATION")
                    val scale = view.scale
                    if (view.width != initialWidth || view.height != initialHeight || scale != initialScale) {
                        throw ScriptFailure("VIEWPORT_CHANGED")
                    }
                    val before = document()
                    val sceneGeneration = scene()
                    val rect = compositor.rectangle()
                    compositor.awaitCommittedFrame()
                    guard()
                    if (before != document()) throw ScriptFailure("SCRIPT_DOCUMENT_CHANGED")
                    if (scene() != sceneGeneration) throw ScriptFailure("CAPTURE_VIEW_UNAVAILABLE")
                    @Suppress("DEPRECATION")
                    val committedScale = view.scale
                    if (view.width != initialWidth ||
                        view.height != initialHeight ||
                        committedScale != initialScale ||
                        compositor.rectangle() != rect
                    ) {
                        throw ScriptFailure("VIEWPORT_CHANGED")
                    }
                    val copyStarted = System.nanoTime()
                    val bitmap = compositor.copy(rect, outputWidth, outputHeight)
                    diagnostics.record(ScriptCaptureDiagnostics.Phase.PIXEL_COPY, System.nanoTime() - copyStarted)
                    try {
                        val now = System.nanoTime()
                        guard()
                        @Suppress("DEPRECATION")
                        val copiedScale = view.scale
                        if (before != document()) throw ScriptFailure("SCRIPT_DOCUMENT_CHANGED")
                        if (scene() != sceneGeneration) throw ScriptFailure("CAPTURE_VIEW_UNAVAILABLE")
                        if (view.width != initialWidth ||
                            view.height != initialHeight ||
                            copiedScale != initialScale ||
                            compositor.rectangle() != rect
                        ) {
                            throw ScriptFailure("VIEWPORT_CHANGED")
                        }
                        Frame(bitmap, (now - run.startedNanos) / 1_000_000.0, before)
                    } catch (error: Throwable) {
                        bitmap.recycle()
                        throw error
                    }
                }
            }
        }

    private fun encode() {
        var gif: ScriptGifEncoder? = null
        var gifFile: File? = null
        var gifStream: FileOutputStream? = null
        var video: ScriptVideoEncoder? = null
        var pending: IntArray? = null
        var pendingTime = -1.0
        var pendingDocument = ""
        var failed: String? = null
        val documents = linkedSetOf<String>()
        try {
            if ("gif" in formats) {
                gifFile = run.artifacts.newFile("gif")
                gifStream = FileOutputStream(gifFile)
                val tap = run.script["tapIndicator"] as? Map<*, *>
                val color = Color.parseColor(tap?.get("color") as? String ?: "#3B82F6")
                gif = ScriptGifEncoder(gifStream, outputWidth, outputHeight, budget, color)
            }
            if ("video" in formats) {
                video = ScriptVideoEncoder(outputWidth, outputHeight, fps, budget) { run.artifacts.newFile("mp4") }
            }
        } catch (_: Exception) {
            failed = "CAPTURE_ENCODING_UNAVAILABLE"
            run.stop(failed)
        }
        kotlinx.coroutines.runBlocking {
            for (command in channel) {
                if (command is Command.Finish) {
                    try {
                        val limit = (options["maxDurationMs"] as? Number)?.toDouble() ?: 60_000.0
                        val terminal = minOf(maxOf(command.terminalMs - originMs, pendingTime + 1), limit)
                        try {
                            if (pending != null) gif?.frame(pending!!, if (gif.frameCount == 0) maxOf(terminal, 10.0) else terminal)
                            gif?.finish()
                            gifStream?.close()
                            if (gif != null && gif.frameCount > 0 && gifFile != null) {
                                register(
                                    gifFile,
                                    "image/gif",
                                    gif.durationMs.toDouble(),
                                    gif.frameCount,
                                    gif.droppedFrames + dropped.get(),
                                    documents,
                                )
                            }
                        } catch (_: Exception) {
                            failed = "CAPTURE_ENCODING_FAILED"
                        }
                        try {
                            video?.let { encoder ->
                                val file = encoder.finish(terminal)
                                if (file != null) {
                                    register(
                                        file,
                                        "video/mp4",
                                        encoder.durationMs,
                                        encoder.frames,
                                        encoder.dropped + dropped.get(),
                                        documents,
                                    )
                                }
                            }
                        } catch (_: Exception) {
                            failed = "CAPTURE_ENCODING_FAILED"
                        }
                        if (budget.exceeded) run.stop("CAPTURE_BUDGET_EXCEEDED")
                        if (failed != null) run.stop(failed!!)
                        command.done.complete(Unit)
                    } catch (_: Exception) {
                        run.stop("CAPTURE_ENCODING_FAILED")
                        command.done.complete(Unit)
                    }
                    break
                }
                command as Command.Sample
                val encodeStarted = System.nanoTime()
                diagnostics.record(ScriptCaptureDiagnostics.Phase.QUEUE, encodeStarted - run.startedNanos - (command.frame.elapsedMs * 1_000_000).toLong())
                try {
                    if (failed != null) throw ScriptFailure(failed!!)
                    val frame = command.frame
                    documents.add(frame.documentId)
                    if (command.step != null) {
                        val bytes =
                            ByteArrayOutputStream().use { stream ->
                                if (!frame.bitmap.compress(Bitmap.CompressFormat.PNG, 100, stream)) {
                                    throw ScriptFailure("CAPTURE_ENCODING_FAILED")
                                }
                                stream.toByteArray()
                            }
                        if (!budget.take(bytes.size.toLong())) throw ScriptFailure("CAPTURE_BUDGET_EXCEEDED")
                        val file = run.artifacts.newFile("png")
                        file.outputStream().use { it.write(bytes) }
                        run.artifacts.register(
                            file,
                            "image/png",
                            mapOf(
                                "width" to outputWidth,
                                "height" to outputHeight,
                                "documentId" to frame.documentId,
                                "actionIndex" to command.step,
                            ),
                        )
                    }
                    if (command.step != null) {
                        command.ack?.complete(Unit)
                        continue
                    }
                    if (pendingTime < 0) {
                        originMs = frame.elapsedMs
                        run.startCapture(originMs, (options["maxDurationMs"] as? Number)?.toLong() ?: 60_000)
                    }
                    val frameTime = frame.elapsedMs - originMs
                    if (pendingTime < 0 || frameTime - pendingTime >= 1000.0 / fps) {
                        val gifStarted = System.nanoTime()
                        val gifAccepted = pending == null || gif?.frame(pending!!, frameTime) != false
                        diagnostics.record(ScriptCaptureDiagnostics.Phase.GIF, System.nanoTime() - gifStarted)
                        if (!gifAccepted) throw ScriptFailure("CAPTURE_BUDGET_EXCEEDED")
                        if (pending != null && gif != null) admission.admit("gif", pendingTime + originMs, pendingDocument)
                        val pixels = IntArray(outputWidth * outputHeight)
                        val pixelsStarted = System.nanoTime()
                        frame.bitmap.getPixels(pixels, 0, outputWidth, 0, 0, outputWidth, outputHeight)
                        diagnostics.record(ScriptCaptureDiagnostics.Phase.PIXEL_READ, System.nanoTime() - pixelsStarted)
                        val videoStarted = System.nanoTime()
                        val videoAccepted = video?.frame(pixels, frameTime, frame.documentId) != false
                        diagnostics.record(ScriptCaptureDiagnostics.Phase.VIDEO, System.nanoTime() - videoStarted)
                        if (!videoAccepted) throw ScriptFailure("CAPTURE_BUDGET_EXCEEDED")
                        video?.let { encoder ->
                            encoder.lastWrittenDocument?.let { writtenDocument ->
                                admission.admit("video", encoder.lastWrittenMs + originMs, writtenDocument)
                            }
                        }
                        pending = if (gif != null) pixels else null
                        pendingDocument = frame.documentId
                        pendingTime = frameTime
                    } else {
                        dropped.incrementAndGet()
                    }
                    command.ack?.complete(Unit)
                } catch (failure: ScriptFailure) {
                    run.stop(failure.code)
                    if (failure.code != "CAPTURE_BUDGET_EXCEEDED") failed = failure.code
                    command.ack?.completeExceptionally(failure)
                } catch (_: Exception) {
                    failed = "CAPTURE_ENCODING_FAILED"
                    run.stop(failed!!)
                    command.ack?.completeExceptionally(ScriptFailure(failed!!))
                } finally {
                    diagnostics.record(ScriptCaptureDiagnostics.Phase.ENCODE, System.nanoTime() - encodeStarted)
                    command.frame.bitmap.recycle()
                }
            }
        }
        runCatching { gifStream?.close() }
    }

    private fun register(
        file: File,
        mime: String,
        duration: Double,
        frames: Int,
        lost: Int,
        documents: Set<String>,
    ) {
        val details =
            mutableMapOf<String, Any?>(
                "width" to outputWidth,
                "height" to outputHeight,
                "durationMs" to duration,
                "frameCount" to frames,
                "droppedFrames" to lost,
                "viewport" to mapOf("width" to initialWidth / initialScale.toDouble(), "height" to initialHeight / initialScale.toDouble()),
            )
        if (documents.size == 1) details["documentId"] = documents.first()
        run.artifacts.register(file, mime, details)
    }
}
