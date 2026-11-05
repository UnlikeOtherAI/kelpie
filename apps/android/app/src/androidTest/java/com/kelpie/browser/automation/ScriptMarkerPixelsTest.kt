package com.kelpie.browser.automation

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Rect
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Test

class ScriptMarkerPixelsTest {
    @Test
    fun chromeBlueFocusRingsAndTextFringesCannotReplaceSceneCenteredCircle() {
        val image = Bitmap.createBitmap(400, 240, Bitmap.Config.ARGB_8888)
        try {
            val canvas = Canvas(image)
            val target = Rect(100, 100, 220, 160)
            val blue = Paint().apply { color = Color.rgb(59, 130, 246) }
            canvas.drawColor(Color.WHITE)
            canvas.drawRect(10f, 10f, 80f, 70f, blue) // Unrelated blue chrome.
            assertNull(ScriptMarkerPixels.locate(image, target))
            blue.style = Paint.Style.STROKE
            blue.strokeWidth = 2f
            canvas.drawRect(target, blue) // Focus ring, empty center.
            assertNull(ScriptMarkerPixels.locate(image, target))
            canvas.drawColor(Color.WHITE)
            blue.style = Paint.Style.FILL
            canvas.drawRect(159f, 105f, 161f, 155f, blue) // Thin blue text fringe.
            assertNull(ScriptMarkerPixels.locate(image, target))
            canvas.drawColor(Color.WHITE)
            canvas.drawCircle(160f, 130f, 20f, blue)
            val actual = ScriptMarkerPixels.locate(image, target)
            assertNotNull(actual)
            assertEquals(160.0, checkNotNull(actual).x, 1.0)
            assertEquals(130.0, actual.y, 1.0)
        } finally {
            image.recycle()
        }
    }
}
