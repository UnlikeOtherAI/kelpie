package com.kelpie.browser.handlers

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ScriptPlaybackLayoutTest {
    @Test
    fun nonMoviePlaybackKeepsLayoutAcrossEveryTerminalOutcome() {
        for (finish in 0..2) {
            val state = ScriptPlaybackState()
            assertTrue(state.start(1, false, movieImmersive = false))
            assertTrue(state.isRecording.value)
            assertFalse(state.isMovieImmersive.value)
            assertFalse(state.start(1, false))
            assertFalse(state.isMovieImmersive.value)
            when (finish) {
                0 -> state.finishSuccess()
                1 -> state.finishAborted()
                else -> state.finishFatalFailure("FAILED", "failed")
            }
            assertFalse(state.isRecording.value)
            assertFalse(state.isMovieImmersive.value)
        }
    }

    @Test
    fun legacyAndMoviePlaybackRemainImmersiveUntilFinished() {
        val state = ScriptPlaybackState()
        assertTrue(state.start(1, false))
        assertTrue(state.isRecording.value)
        assertTrue(state.isMovieImmersive.value)
        state.finishSuccess()
        assertFalse(state.isRecording.value)
        assertFalse(state.isMovieImmersive.value)
        assertTrue(state.start(1, false, movieImmersive = true))
        assertTrue(state.isMovieImmersive.value)
        state.finishAborted()
        assertFalse(state.isMovieImmersive.value)
    }
}
