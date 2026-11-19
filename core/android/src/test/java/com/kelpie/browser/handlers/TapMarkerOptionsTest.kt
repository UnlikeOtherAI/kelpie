package com.kelpie.browser.handlers

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class TapMarkerOptionsTest {
    @Test
    fun defaultsApplyToOmittedFields() {
        assertEquals(TapMarkerOptions("circle", 550), TapMarkerOptions.parse(emptyMap()))
        assertEquals(TapMarkerOptions("circle", 0), TapMarkerOptions.parse(mapOf("marker" to mapOf("durationMs" to 0))))
        assertEquals(
            TapMarkerOptions("crosshair-coordinates", 550),
            TapMarkerOptions.parse(mapOf("marker" to mapOf("style" to "crosshair-coordinates"))),
        )
    }

    @Test
    fun invalidMarkersCannotReachTheRenderer() {
        val invalidMarkers =
            listOf(
                null,
                mapOf("style" to "square"),
                mapOf("style" to null),
                mapOf("durationMs" to false),
                mapOf("durationMs" to 1.5),
                mapOf("durationMs" to -1),
                mapOf("durationMs" to 2147483648L),
                mapOf("extra" to 1),
            )
        for (marker in invalidMarkers) {
            assertNull(TapMarkerOptions.parse(mapOf("marker" to marker)))
        }
    }
}
