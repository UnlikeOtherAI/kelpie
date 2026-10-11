package com.kelpie.browser.connect

import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Test

class ConnectScreenshotBudgetTest {
    private fun shot(
        format: String,
        size: Int,
    ) = mapOf("success" to true, "format" to format, "image" to "A".repeat(size))

    @Test
    fun smallScreenshotPassesThroughUnchanged() =
        runBlocking {
            val calls = mutableListOf<Map<String, Any?>>()
            val result =
                ConnectScreenshotBudget.fit(mapOf("tabId" to "t")) {
                    calls += it
                    shot("png", 10)
                }
            assertEquals("png", result["format"])
            assertEquals(listOf(mapOf<String, Any?>("tabId" to "t")), calls)
        }

    @Test
    fun oversizedPngFallsBackToFirstFittingJpeg() =
        runBlocking {
            val calls = mutableListOf<Map<String, Any?>>()
            val result =
                ConnectScreenshotBudget.fit(mapOf("tabId" to "t")) {
                    calls += it
                    if (it["quality"] == 60) shot("jpeg", 100) else shot(it["format"] as? String ?: "png", 700 * 1024)
                }
            assertEquals("jpeg", result["format"])
            assertEquals(listOf(null, 80, 60), calls.map { it["quality"] })
            assertEquals("t", calls.last()["tabId"])
        }

    @Test
    fun nothingFittingIsRefusedAsTooLarge() =
        runBlocking {
            val result = ConnectScreenshotBudget.fit(emptyMap()) { shot("jpeg", 700 * 1024) }
            assertEquals(false, result["success"])
            assertEquals("SCREENSHOT_TOO_LARGE", (result["error"] as Map<*, *>)["code"])
        }

    @Test
    fun fenceRefusalDuringRecaptureIsReturned() =
        runBlocking {
            var call = 0
            val refused = mapOf("success" to false, "error" to mapOf("code" to "TAB_CHANGED"))
            val result =
                ConnectScreenshotBudget.fit(emptyMap()) {
                    if (call++ == 0) shot("png", 700 * 1024) else refused
                }
            assertEquals(refused, result)
            assertEquals(2, call)
        }
}
