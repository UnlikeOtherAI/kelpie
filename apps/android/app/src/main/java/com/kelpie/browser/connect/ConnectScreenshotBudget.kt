package com.kelpie.browser.connect

import com.kelpie.browser.network.errorResponse

/**
 * Account job results are bounded by the connect ledger (768 KiB serialized).
 * A viewport PNG of a photographic or large page can exceed that once base64
 * encoded, so account screenshots recapture as progressively smaller JPEGs.
 * The native result reports its real format, so the typed image stays truthful.
 */
object ConnectScreenshotBudget {
    /** Base64 characters, leaving headroom for the canonical envelope and pins. */
    const val MAX_IMAGE_CHARACTERS = 640 * 1024
    val JPEG_QUALITIES = listOf(80, 60, 40)

    suspend fun fit(
        params: Map<String, Any?>,
        capture: suspend (Map<String, Any?>) -> Map<String, Any?>,
    ): Map<String, Any?> {
        val first = capture(params)
        if (!oversized(first)) return first
        for (quality in fallbackQualities(params)) {
            val result = capture(params + mapOf("format" to "jpeg", "quality" to quality))
            if (!oversized(result)) return result
        }
        return errorResponse("SCREENSHOT_TOO_LARGE", "The screenshot exceeds the account result limit even as a JPEG.")
    }

    /** A capture that already was a JPEG only retries at lower qualities. */
    private fun fallbackQualities(params: Map<String, Any?>): List<Int> {
        if (params["format"] != "jpeg") return JPEG_QUALITIES
        val initial = (params["quality"] as? Number)?.toInt() ?: 80
        return JPEG_QUALITIES.filter { it < initial }
    }

    /** Only a successful capture can be oversized; failures and fence refusals return unchanged. */
    private fun oversized(result: Map<String, Any?>): Boolean {
        if (result["success"] != true) return false
        val image = result["image"] as? String ?: return false
        return image.length > MAX_IMAGE_CHARACTERS
    }
}
