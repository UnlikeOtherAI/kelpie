package com.kelpie.browser.ui

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ScriptCaptureSceneEffectTest {
    @Test
    fun everyOccludingLayerRefusesCertificationUntilCleared() {
        assertFalse(scriptSceneCertified(false, emptyList()))
        assertTrue(scriptSceneCertified(true, List(14) { false }))
        for (index in 0 until 14) {
            val active = List(14) { it == index }
            assertFalse(scriptSceneCertified(true, active))
            assertTrue(scriptSceneCertified(true, active.map { false }))
        }
    }
}
