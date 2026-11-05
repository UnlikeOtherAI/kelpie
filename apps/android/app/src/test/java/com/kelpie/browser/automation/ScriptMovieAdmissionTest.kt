package com.kelpie.browser.automation

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ScriptMovieAdmissionTest {
    @Test
    fun everyRequestedMovieNeedsEncodedOldDocumentFrameAfterMarker() {
        val admission = ScriptMovieAdmission(listOf("gif", "video", "screenshots"))
        assertTrue(admission.enabled())
        assertFalse(admission.contains(10.25, "old"))
        admission.admit("gif", 10.0, "old")
        admission.admit("video", 11.0, "old")
        assertFalse(admission.contains(10.25, "old"))
        admission.admit("gif", 11.0, "old")
        assertTrue(admission.contains(10.25, "old"))
        admission.admit("video", 12.0, "new")
        assertFalse(admission.contains(10.25, "old"))
        admission.admit("video", 11.5, "old") // Late acknowledgement cannot undo a newer document.
        assertFalse(admission.contains(10.25, "old"))
        admission.admit("gif", Double.NaN, "new")
        assertFalse(admission.contains(10.25, "new"))
        admission.admit("gif", 12.0, "new")
        assertTrue(admission.contains(10.25, "new"))
    }

    @Test
    fun screenshotOnlyNeverWaitsForMovieAcknowledgement() {
        val admission = ScriptMovieAdmission(listOf("screenshots"))
        assertFalse(admission.enabled())
        assertFalse(admission.contains(0.0, "document"))
    }
}
