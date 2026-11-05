package com.kelpie.browser.automation

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ScriptMovieLayoutTest {
    @Test
    fun onlyContinuousMovieFormatsEnterImmersiveLayout() {
        assertFalse(scriptUsesMovieLayout(emptyMap()))
        assertFalse(scriptUsesMovieLayout(mapOf("formats" to listOf("screenshots"))))
        assertTrue(scriptUsesMovieLayout(mapOf("formats" to listOf("gif"))))
        assertTrue(scriptUsesMovieLayout(mapOf("formats" to listOf("video", "screenshots"))))
    }
}