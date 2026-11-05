package com.kelpie.browser.automation

import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Path
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.view.View
import com.kelpie.browser.BuildConfig
import kotlinx.coroutines.Job
import java.lang.ref.WeakReference

/** Live native overlay and captured pixels consume this one timeline and renderer. */
class ScriptOverlay {
    data class Pointer(
        val fromX: Double,
        val fromY: Double,
        val toX: Double,
        val toY: Double,
        val start: Long,
        val durationMs: Double,
        val curveS: Boolean,
    )

    data class Tap(
        val x: Double,
        val y: Double,
        val start: Long,
        val radius: Double,
        val durationMs: Double,
        val color: Int,
        val wobble: Boolean,
        val fade: Boolean,
        val held: Boolean = false,
    )

    data class Commentary(
        val text: String,
        val start: Long,
        val durationMs: Double,
        val position: String,
    )

    data class RetainedTap(
        val generation: Long,
        val owner: String,
        val document: String,
        val deadlineNs: Long,
    )

    private var activeOwner: String? = null
    private var generation = 0L
    private var retainedOwner: String? = null
    private var retainedDeadlineNs = 0L
    private var retainedGuard: (() -> Boolean)? = null
    private var retirementJob: Job? = null
    private var retirementTimeout: Runnable? = null
    private var markerFrame: ScriptOverlayFrame? = null
    private var pointer: Pointer? = null
    private var tap: Tap? = null
    private var markerDrawLogged = false
    private var commentary: Commentary? = null
    private var document: String? = null
    private var viewportLeft = 0.0
    private var viewportTop = 0.0
    private var viewportWidth = 0.0
    private var viewportHeight = 0.0
    private var view = WeakReference<View>(null)
    private val main = Handler(Looper.getMainLooper())

    @Synchronized
    fun attach(target: View) {
        if (view.get() !== target && retainedOwner != null) { scriptMarkerTrace("view", "VIEW_REPLACED"); clear() }
        view = WeakReference(target)
        changed()
    }

    @Synchronized
    fun viewport(
        width: Double,
        height: Double,
        documentId: String,
        offsetLeft: Double = 0.0,
        offsetTop: Double = 0.0,
        preserveExisting: Boolean = false,
    ) {
        if (preserveExisting && document == documentId && viewportWidth > 0) return
        viewportLeft = offsetLeft
        viewportTop = offsetTop
        document = documentId
        viewportWidth = width
        viewportHeight = height
        changed()
    }

    @Synchronized
    fun move(value: Pointer) {
        pointer = value
        changed()
    }

    @Synchronized
    fun indicate(value: Tap) {
        generation++
        retainedOwner = null
        retainedGuard = null
        markerFrame = null
        tap = value
        markerDrawLogged = false
        if (BuildConfig.DEBUG) {
            Log.d("KelpieMarkerTiming", "stage=published nowNs=${System.nanoTime()} held=${value.held} attached=${view.get()?.isAttachedToWindow == true}")
        }
        changed()
    }

    @Synchronized
    fun narrate(value: Commentary) {
        commentary = value
        changed()
    }

    @Synchronized
    fun clear() {
        retirementJob?.cancel()
        retirementJob = null
        retirementTimeout?.let(main::removeCallbacks)
        retirementTimeout = null
        generation++
        retainedOwner = null
        retainedDeadlineNs = 0L
        retainedGuard = null
        markerFrame = null
        pointer = null
        tap = null
        commentary = null
        document = null
        viewportWidth = 0.0
        viewportHeight = 0.0
        viewportLeft = 0.0
        viewportTop = 0.0
        changed()
    }

    @Synchronized
    fun claimRun(owner: String) {
        clear()
        activeOwner = owner
    }

    @Synchronized
    fun clearOwned(owner: String) {
        if (activeOwner == owner) {
            clear()
            activeOwner = null
        }
    }

    @Synchronized
    fun bindRetirementFrame(target: android.webkit.WebView) {
        val presentation = view.get()
        if (presentation == null) scriptMarkerTrace("bind", "OVERLAY_REFERENCE_MISSING")
        markerFrame = presentation?.let { ScriptOverlayFrame.capture(target, it) }
    }

    /** Keeps only the final live tap until its original deadline; never extends it. */
    @Synchronized
    fun retainFinalTap(
        owner: String,
        now: Long,
        guard: () -> Boolean,
    ): RetainedTap? {
        if (activeOwner != owner) { scriptMarkerTrace("retain", "OWNER_CHANGED"); return null }
        val current = tap ?: run { scriptMarkerTrace("retain", "NO_TAP"); return null }
        val currentDocument = document ?: run { scriptMarkerTrace("retain", "NO_DOCUMENT"); return null }
        if (markerFrame?.matches() != true) { scriptMarkerTrace("retain", "FRAME_INVALID"); return null }
        if (!runCatching(guard).getOrDefault(false)) { scriptMarkerTrace("retain", "GUARD_FAILED"); return null }
        if (current.held || !current.durationMs.isFinite() || current.durationMs <= 0.0) { scriptMarkerTrace("retain", "TAP_INVALID"); return null }
        val deadline = current.start + (current.durationMs.coerceAtMost(5_000.0) * 1_000_000).toLong()
        if (deadline <= now) { scriptMarkerTrace("retain", "EXPIRED"); return null }
        pointer = null
        commentary = null
        retainedOwner = owner
        retainedDeadlineNs = deadline
        retainedGuard = guard
        scriptMarkerTrace("retain", "ACCEPTED")
        val retained = RetainedTap(generation, owner, currentDocument, deadline)
        val delayMs = ((deadline - now + 999_999) / 1_000_000).coerceAtLeast(1)
        val timeout = Runnable { scriptMarkerTrace("timer", "EXPIRED"); clearRetained(retained) }
        retirementTimeout = timeout
        main.postDelayed(timeout, delayMs)
        changed()
        return retained
    }

    @Synchronized
    fun installRetirementJob(
        value: RetainedTap,
        job: Job,
    ) {
        if (isRetained(value)) retirementJob = job else job.cancel()
    }

    @Synchronized
    fun isRetained(value: RetainedTap): Boolean = generation == value.generation && retainedOwner == value.owner

    @Synchronized
    fun clearRetained(value: RetainedTap) {
        if (isRetained(value)) clearOwned(value.owner)
    }

    @Synchronized
    fun clearRetainedOwner(owner: String) {
        if (retainedOwner == owner) clearOwned(owner)
    }

    @Synchronized
    fun isAttachedView(target: View): Boolean = view.get() === target

    @Synchronized
    fun clearRetainedForView(target: View) {
        if (view.get() === target && retainedOwner != null) {
            scriptMarkerTrace("view", "VIEW_LOST")
            retainedOwner?.let(::clearOwned)
        }
    }

    @Synchronized
    fun draw(
        canvas: Canvas,
        width: Int,
        height: Int,
        now: Long,
        documentId: String?,
    ): Boolean {
        if (retainedOwner != null) {
            val reason =
                when {
                    now >= retainedDeadlineNs -> "EXPIRED"
                    documentId != document -> "DOCUMENT_CHANGED"
                    markerFrame?.matches() != true -> "FRAME_INVALID"
                    !runCatching { retainedGuard?.invoke() == true }.getOrDefault(false) -> "GUARD_FAILED"
                    else -> null
                }
            if (reason != null) {
                scriptMarkerTrace("draw", reason)
                clear()
                return false
            }
        }
        if (BuildConfig.DEBUG && tap != null && !markerDrawLogged) {
            markerDrawLogged = true
            Log.d(
                "KelpieMarkerTiming",
                "stage=firstDraw nowNs=$now documentMatch=${documentId == document} viewportReady=${viewportWidth > 0 && viewportHeight > 0} width=$width height=$height",
            )
        }
        if (viewportWidth <= 0 || viewportHeight <= 0 || documentId != document) return pointer != null || tap != null
        canvas.save()
        canvas.scale((width / viewportWidth).toFloat(), (height / viewportHeight).toFloat())
        val paint = Paint(Paint.ANTI_ALIAS_FLAG)
        var animate = false
        canvas.save()
        canvas.translate(-viewportLeft.toFloat(), -viewportTop.toFloat())
        pointer?.let { motion ->
            val elapsed = (now - motion.start) / 1_000_000.0
            val point =
                ScriptNative.pointerPosition(
                    motion.fromX,
                    motion.fromY,
                    motion.toX,
                    motion.toY,
                    motion.curveS,
                    elapsed,
                    motion.durationMs,
                )
            val x = point[0].toFloat()
            val y = point[1].toFloat()
            val arrow =
                Path().apply {
                    moveTo(x, y)
                    lineTo(x, y + 20)
                    lineTo(x + 5, y + 15)
                    lineTo(x + 10, y + 24)
                    lineTo(x + 15, y + 21)
                    lineTo(x + 10, y + 12)
                    lineTo(x + 17, y + 12)
                    close()
                }
            paint.color = Color.BLACK
            paint.style = Paint.Style.STROKE
            paint.strokeWidth = 2f
            canvas.drawPath(arrow, paint)
            paint.style = Paint.Style.FILL
            paint.color = Color.WHITE
            canvas.drawPath(arrow, paint)
            animate = true
        }
        tap?.let { indicator ->
            val elapsed = if (indicator.held) 0.0 else (now - indicator.start) / 1_000_000.0
            if (elapsed < indicator.durationMs) {
                val state = ScriptNative.tapPresentation(elapsed, indicator.durationMs, indicator.wobble, indicator.fade)
                paint.style = Paint.Style.FILL
                paint.color = indicator.color
                paint.alpha = (state[1] * 179).toInt().coerceIn(0, 255)
                canvas.drawCircle(indicator.x.toFloat(), indicator.y.toFloat(), (indicator.radius * state[0]).toFloat(), paint)
                animate = true
            }
        }
        canvas.restore()
        commentary?.let { item ->
            val elapsed = (now - item.start) / 1_000_000.0
            if (elapsed < item.durationMs) {
                val text = item.text.take(1024)
                paint.alpha = 230
                paint.textSize = 15f
                val available = (viewportWidth - 48).toFloat().coerceAtLeast(1f)
                val count = paint.breakText(text, true, available, null)
                val display = text.take(count)
                val boxWidth = paint.measureText(display) + 24
                val left = ((viewportWidth - boxWidth) / 2).toFloat()
                val top =
                    when (item.position) {
                        "top" -> 24f
                        "center" -> (viewportHeight / 2 - 20).toFloat()
                        else -> (viewportHeight - 68).toFloat()
                    }
                paint.color = Color.BLACK
                canvas.drawRoundRect(left, top, left + boxWidth, top + 40, 12f, 12f, paint)
                paint.color = Color.WHITE
                canvas.drawText(display, left + 12, top + 25, paint)
                animate = true
            }
        }
        canvas.restore()
        return animate
    }

    private fun changed() {
        main.post { view.get()?.invalidate() }
    }
}

class ScriptOverlayView(
    context: Context,
    private val overlay: ScriptOverlay,
    private val document: () -> String?,
    private val recording: () -> Boolean,
) : View(context) {
    init {
        isClickable = false
        isFocusable = false
        importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_NO
        overlay.attach(this)
    }

    override fun onDetachedFromWindow() {
        overlay.clearRetainedForView(this)
        super.onDetachedFromWindow()
    }

    override fun onWindowFocusChanged(hasWindowFocus: Boolean) {
        super.onWindowFocusChanged(hasWindowFocus)
        if (!hasWindowFocus) overlay.clearRetainedForView(this)
    }

    override fun onWindowVisibilityChanged(visibility: Int) {
        super.onWindowVisibilityChanged(visibility)
        if (visibility != VISIBLE) overlay.clearRetainedForView(this)
    }

    override fun onTouchEvent(event: android.view.MotionEvent): Boolean = recording()

    override fun onDraw(canvas: Canvas) {
        if (!overlay.isAttachedView(this)) return
        if (overlay.draw(canvas, width, height, System.nanoTime(), document())) postInvalidateOnAnimation()
    }
}
