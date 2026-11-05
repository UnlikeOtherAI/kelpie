package com.kelpie.browser.ui

import androidx.compose.foundation.clickable
import androidx.compose.foundation.focusable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.size
import androidx.compose.material3.Text
import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.input.key.Key
import androidx.compose.ui.input.key.onKeyEvent
import androidx.compose.ui.test.ExperimentalTestApi
import androidx.compose.ui.test.click
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.onRoot
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performKeyInput
import androidx.compose.ui.test.performTouchInput
import androidx.compose.ui.test.pressKey
import androidx.compose.ui.unit.dp
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test

@OptIn(ExperimentalTestApi::class)
class ScriptInputBlockTest {
    @get:Rule val ui = createComposeRule()

    @Test
    fun activePlaybackBlocksChromeAndLeavesSeparateStopAvailable() {
        val active = mutableStateOf(false)
        val requester = FocusRequester()
        var keyEvents = 0
        var chromeClicks = 0
        var stopClicks = 0
        ui.setContent {
            Column {
                Box(Modifier.size(100.dp).scriptInputBlock(active.value)) {
                    Box(
                        Modifier
                            .size(100.dp)
                            .focusRequester(requester)
                            .onKeyEvent {
                                keyEvents++
                                true
                            }.focusable()
                            .clickable { chromeClicks++ },
                    ) { Text("Browser control") }
                }
                Box(Modifier.size(100.dp).clickable { stopClicks++ }) { Text("Stop") }
            }
        }
        ui.runOnIdle { requester.requestFocus() }
        ui.onRoot().performKeyInput { pressKey(Key.Enter) }
        ui.runOnIdle {
            assertTrue("Control did not receive the baseline key", keyEvents > 0)
            keyEvents = 0
            active.value = true
        }
        ui.onRoot().performKeyInput { pressKey(Key.Enter) }
        ui.runOnIdle { assertEquals(0, keyEvents) }
        ui.onNodeWithText("Browser control").assertDoesNotExist()
        ui.onRoot().performTouchInput { click(Offset(20f, 20f)) }
        ui.onNodeWithText("Stop").performClick()
        ui.runOnIdle {
            assertEquals(0, chromeClicks)
            assertEquals(1, stopClicks)
            active.value = false
        }
        ui.onNodeWithText("Browser control").performClick()
        ui.runOnIdle { assertEquals(1, chromeClicks) }
    }
}
