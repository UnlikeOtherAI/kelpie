package com.kelpie.browser.automation

import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Path
import android.os.Handler
import android.os.Looper
import android.view.View
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

    private var pointer: Pointer? = null
    private var tap: Tap? = null
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
        tap = value
        changed()
    }

    @Synchronized
    fun narrate(value: Commentary) {
        commentary = value
        changed()
    }

    @Synchronized
    fun clear() {
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
    fun draw(
        canvas: Canvas,
        width: Int,
        height: Int,
        now: Long,
        documentId: String?,
    ): Boolean {
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

    override fun onTouchEvent(event: android.view.MotionEvent): Boolean = recording()

    override fun onDraw(canvas: Canvas) {
        if (overlay.draw(canvas, width, height, System.nanoTime(), document())) postInvalidateOnAnimation()
    }
}
