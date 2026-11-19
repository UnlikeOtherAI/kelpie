package com.kelpie.browser.handlers

internal data class TapMarkerOptions(
    val style: String,
    val durationMs: Int,
) {
    companion object {
        val DEFAULTS = TapMarkerOptions("circle", 550)
        const val INVALID_MESSAGE =
            "marker must contain only a supported style and/or an integer durationMs from 0 to 2147483647"

        fun parse(body: Map<String, Any?>): TapMarkerOptions? {
            if ("marker" !in body) return DEFAULTS
            val marker = body["marker"] as? Map<*, *> ?: return null
            if (marker.keys.any { it != "style" && it != "durationMs" }) return null
            val style = if ("style" in marker) marker["style"] as? String ?: return null else DEFAULTS.style
            if (style != "circle" && style != "crosshair-coordinates") return null
            val duration = if ("durationMs" in marker) marker["durationMs"] else DEFAULTS.durationMs
            val number = (duration as? Number)?.toDouble() ?: return null
            if (number !in 0.0..Int.MAX_VALUE.toDouble() || number != number.toInt().toDouble()) return null
            return TapMarkerOptions(style, number.toInt())
        }
    }

    fun script(
        source: String,
        x: Double,
        y: Double,
        rgb: String,
    ): String = "($source)($x, $y, '${JSEscape.string(rgb)}', '$style', $durationMs);"
}
