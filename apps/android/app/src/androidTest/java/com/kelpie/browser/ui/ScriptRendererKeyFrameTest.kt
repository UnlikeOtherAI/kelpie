package com.kelpie.browser.ui

import android.view.KeyEvent
import android.view.View
import android.widget.FrameLayout
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import com.kelpie.browser.MainActivity
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test

/** Native child dispatch, separate from the public WebView playback test. */
class ScriptRendererKeyFrameTest {
    @get:Rule val ui = createAndroidComposeRule<MainActivity>()

    @Test
    fun rendererKeysAreBlockedOnlyDuringPlaybackAndSystemKeysAreDelegated() {
        var active = false
        val delivered = mutableListOf<Pair<Int, Int>>()
        ui.runOnUiThread {
            val frame = ScriptRendererKeyFrame(ui.activity) { active }
            val child =
                object : View(ui.activity) {
                    override fun dispatchKeyEvent(event: KeyEvent): Boolean {
                        delivered.add(event.keyCode to event.action)
                        return true
                    }
                }
            child.isFocusable = true
            frame.addView(child, FrameLayout.LayoutParams(200, 200))
            ui.activity.setContentView(frame)
            assertTrue(child.requestFocus())

            fun send(code: Int) {
                frame.dispatchKeyEvent(KeyEvent(KeyEvent.ACTION_DOWN, code))
                frame.dispatchKeyEvent(KeyEvent(KeyEvent.ACTION_UP, code))
            }

            send(KeyEvent.KEYCODE_ENTER)
            assertEquals(2, delivered.size)
            active = true
            send(KeyEvent.KEYCODE_ENTER)
            assertEquals(2, delivered.size)
            assertTrue(KeyEvent(KeyEvent.ACTION_DOWN, KeyEvent.KEYCODE_VOLUME_UP).isSystem)
            send(KeyEvent.KEYCODE_VOLUME_UP)
            assertEquals(4, delivered.size)
            assertEquals(KeyEvent.KEYCODE_VOLUME_UP, delivered[2].first)
            assertEquals(KeyEvent.KEYCODE_VOLUME_UP, delivered[3].first)
            active = false
            send(KeyEvent.KEYCODE_ENTER)
            assertEquals(6, delivered.size)
            assertEquals(KeyEvent.KEYCODE_ENTER to KeyEvent.ACTION_DOWN, delivered[4])
            assertEquals(KeyEvent.KEYCODE_ENTER to KeyEvent.ACTION_UP, delivered[5])
        }
    }
}
