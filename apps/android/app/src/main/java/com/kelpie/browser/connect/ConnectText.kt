package com.kelpie.browser.connect

/** Wire lengths count UTF-16 units. Never split or emit an unpaired surrogate. */
object ConnectText {
    fun bounded(
        text: String,
        limit: Int,
    ): String {
        val result = StringBuilder()
        var offset = 0
        while (offset < text.length) {
            val observed = text.codePointAt(offset)
            val point = if (observed in 0xD800..0xDFFF) 0xFFFD else observed
            if (result.length + Character.charCount(point) > limit) break
            result.appendCodePoint(point)
            offset += Character.charCount(observed)
        }
        return result.toString()
    }
}
