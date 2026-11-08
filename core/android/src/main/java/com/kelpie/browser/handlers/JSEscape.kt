package com.kelpie.browser.handlers

/**
 * Escapes a string for safe interpolation inside a JavaScript single-quoted
 * string literal. Mirrors the Swift `JSEscape.string` helper on iOS/macOS so
 * that all three platforms produce identical literals.
 */
object JSEscape {
    private const val DEFAULT_OVERLAY_RGB = "59,130,246"

    fun string(value: String): String {
        val sb = StringBuilder(value.length + 8)
        for (ch in value) {
            when (ch) {
                '\\' -> sb.append("\\\\")
                '\'' -> sb.append("\\'")
                '"' -> sb.append("\\\"")
                '\n' -> sb.append("\\n")
                '\r' -> sb.append("\\r")
                '\t' -> sb.append("\\t")
                '\u2028' -> sb.append("\\u2028")
                '\u2029' -> sb.append("\\u2029")
                else -> sb.append(ch)
            }
        }
        return sb.toString()
    }

    fun hexToRGB(hex: String?): String {
        val normalized = hex?.removePrefix("#") ?: return DEFAULT_OVERLAY_RGB
        if (normalized.length != 6) return DEFAULT_OVERLAY_RGB
        return try {
            val red = normalized.substring(0, 2).toInt(16)
            val green = normalized.substring(2, 4).toInt(16)
            val blue = normalized.substring(4, 6).toInt(16)
            "$red,$green,$blue"
        } catch (_: NumberFormatException) {
            DEFAULT_OVERLAY_RGB
        }
    }
}
