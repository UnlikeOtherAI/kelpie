package com.kelpie.browser.ui

import com.kelpie.browser.handlers.ScriptPlaybackState
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ScriptRendererKeyPolicyTest {
    @Test
    fun browserKeysRemainBlockedUntilEveryTerminalPathAndSystemKeysRemainAvailable() {
        val state = ScriptPlaybackState()

        fun assertPolicy(active: Boolean) {
            assertTrue(state.isRecording.value == active)
            assertTrue(blocksScriptBrowserKey(active, system = false) == active)
            assertFalse(blocksScriptBrowserKey(active, system = true))
        }

        assertPolicy(false)
        assertTrue(state.start(1, continueOnError = false, movieImmersive = false))
        assertPolicy(true)
        state.requestAbort()
        assertPolicy(true)
        state.finishAborted()
        assertPolicy(false)
        assertTrue(state.start(1, continueOnError = false))
        state.finishFatalFailure("FAILED", "failed")
        assertPolicy(false)
        assertTrue(state.start(1, continueOnError = false))
        state.finishSuccess()
        assertPolicy(false)
    }
}
