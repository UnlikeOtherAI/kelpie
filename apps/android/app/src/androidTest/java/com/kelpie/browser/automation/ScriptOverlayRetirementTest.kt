package com.kelpie.browser.automation

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.view.View
import android.view.ViewGroup
import android.webkit.WebView
import android.widget.FrameLayout
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import com.kelpie.browser.MainActivity
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test

/** Exercises ownership and physical-frame fencing against an attached native renderer. */
class ScriptOverlayRetirementTest {
    @get:Rule val ui = createAndroidComposeRule<MainActivity>()

    @Test
    fun exactOwnerAndViewFenceRetiredMarker() {
        lateinit var renderer: WebView
        lateinit var container: FrameLayout
        ui.runOnUiThread {
            container = FrameLayout(ui.activity)
            renderer = WebView(ui.activity)
            container.addView(renderer, FrameLayout.LayoutParams(300, 300))
            ui.activity.addContentView(container, ViewGroup.LayoutParams(300, 300))
        }
        try {
            ui.waitUntil(10_000) { renderer.isAttachedToWindow && renderer.width > 0 && renderer.height > 0 }
            ui.runOnUiThread {
                val overlay = ScriptOverlay()
                val oldView = View(ui.activity)
                val newView = View(ui.activity)
                container.addView(oldView, FrameLayout.LayoutParams(300, 300))
                container.addView(newView, FrameLayout.LayoutParams(300, 300))
                oldView.measure(View.MeasureSpec.makeMeasureSpec(300, View.MeasureSpec.EXACTLY), View.MeasureSpec.makeMeasureSpec(300, View.MeasureSpec.EXACTLY))
                oldView.layout(0, 0, 300, 300)
                newView.measure(View.MeasureSpec.makeMeasureSpec(300, View.MeasureSpec.EXACTLY), View.MeasureSpec.makeMeasureSpec(300, View.MeasureSpec.EXACTLY))
                newView.layout(0, 0, 300, 300)
                overlay.attach(oldView)
                overlay.claimRun("first")
                overlay.viewport(300.0, 300.0, "document")
                overlay.indicate(ScriptOverlay.Tap(50.0, 50.0, System.nanoTime(), 20.0, 5000.0, Color.RED, false, true))
                overlay.bindRetirementFrame(renderer)
                val first = overlay.retainFinalTap("first", System.nanoTime()) { true }
                assertNotNull(first)

                overlay.attach(newView)
                assertFalse(overlay.isRetained(checkNotNull(first)))
                overlay.claimRun("second")
                overlay.viewport(300.0, 300.0, "document")
                overlay.indicate(ScriptOverlay.Tap(60.0, 60.0, System.nanoTime(), 20.0, 5000.0, Color.RED, false, true))
                overlay.bindRetirementFrame(renderer)
                val second = overlay.retainFinalTap("second", System.nanoTime()) { true }
                assertNotNull(second)
                overlay.clearRetained(first)
                overlay.clearOwned("first")
                overlay.clearRetainedForView(oldView)
                assertTrue(overlay.isRetained(checkNotNull(second)))
                overlay.clearRetainedForView(newView)
                assertFalse(overlay.isRetained(second))
            }
        } finally {
            ui.runOnUiThread {
                (container.parent as? ViewGroup)?.removeView(container)
                renderer.destroy()
            }
        }
    }

    @Test
    fun changedNativeFrameAndInvalidAuthorityRefuseRetirement() {
        lateinit var renderer: WebView
        lateinit var container: FrameLayout
        ui.runOnUiThread {
            container = FrameLayout(ui.activity)
            renderer = WebView(ui.activity)
            container.addView(renderer, FrameLayout.LayoutParams(300, 300))
            ui.activity.addContentView(container, ViewGroup.LayoutParams(300, 300))
        }
        try {
            ui.waitUntil(10_000) { renderer.isAttachedToWindow && renderer.width > 0 && renderer.height > 0 }
            ui.runOnUiThread {
                val overlay = ScriptOverlay()
                val presentation = View(ui.activity)
                container.addView(presentation, FrameLayout.LayoutParams(300, 300))
                presentation.measure(View.MeasureSpec.makeMeasureSpec(300, View.MeasureSpec.EXACTLY), View.MeasureSpec.makeMeasureSpec(300, View.MeasureSpec.EXACTLY))
                presentation.layout(0, 0, 300, 300)
                overlay.attach(presentation)
                overlay.claimRun("owner")
                overlay.viewport(300.0, 300.0, "document")
                overlay.indicate(ScriptOverlay.Tap(50.0, 50.0, System.nanoTime(), 20.0, 5000.0, Color.RED, false, true))
                overlay.bindRetirementFrame(renderer)
                assertNull(overlay.retainFinalTap("owner", System.nanoTime()) { false })
                renderer.translationX = 2f
                assertNull(overlay.retainFinalTap("owner", System.nanoTime()) { true })
                renderer.translationX = 0f
                val retained = checkNotNull(overlay.retainFinalTap("owner", System.nanoTime()) { true })
                presentation.translationX = 1f
                val bitmap = Bitmap.createBitmap(300, 300, Bitmap.Config.ARGB_8888)
                assertFalse(overlay.draw(Canvas(bitmap), 300, 300, System.nanoTime(), "document"))
                assertFalse(overlay.isRetained(retained))
                bitmap.recycle()
            }
        } finally {
            ui.runOnUiThread {
                (container.parent as? ViewGroup)?.removeView(container)
                renderer.destroy()
            }
        }
    }
}