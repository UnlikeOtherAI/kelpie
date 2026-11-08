package com.kelpie.browser.ai.openai

import java.io.ByteArrayOutputStream

data class SSEEvent(
    val event: String?,
    val data: String,
    val id: String?,
)

/**
 * Byte-oriented Server-Sent Events parser.
 *
 * Lines are only decoded as UTF-8 once complete, so multi-byte sequences split across
 * network chunks survive. Accepts `\n`, `\r\n` and `\r` line endings (including a `\r\n`
 * pair split across chunks), comment lines, `event:` / `id:` fields and multi-line `data:`.
 */
class SSEParser(
    private val onEvent: (SSEEvent) -> Unit,
    private val onComment: (String) -> Unit = {},
) {
    private val line = ByteArrayOutputStream()
    private var skipNextLineFeed = false
    private val data = StringBuilder()
    private var hasData = false
    private var eventName: String? = null
    private var lastId: String? = null

    fun feed(
        bytes: ByteArray,
        length: Int = bytes.size,
    ) {
        for (index in 0 until length) {
            val byte = bytes[index]
            when (byte) {
                LF -> {
                    if (skipNextLineFeed) {
                        skipNextLineFeed = false
                    } else {
                        endLine()
                    }
                }
                CR -> {
                    skipNextLineFeed = true
                    endLine()
                }
                else -> {
                    skipNextLineFeed = false
                    line.write(byte.toInt())
                }
            }
        }
    }

    /** Flushes a final line / event when the stream ends without a trailing blank line. */
    fun finish() {
        if (line.size() > 0) endLine()
        dispatch()
    }

    private fun endLine() {
        val text = line.toString(Charsets.UTF_8.name())
        line.reset()
        processLine(text)
    }

    private fun processLine(text: String) {
        if (text.isEmpty()) {
            dispatch()
            return
        }
        if (text.startsWith(":")) {
            onComment(text.substring(1).trim())
            return
        }
        val colon = text.indexOf(':')
        val field = if (colon >= 0) text.substring(0, colon) else text
        var value = if (colon >= 0) text.substring(colon + 1) else ""
        if (value.startsWith(" ")) value = value.substring(1)
        when (field) {
            "data" -> {
                if (hasData) data.append('\n')
                data.append(value)
                hasData = true
            }
            "event" -> eventName = value
            "id" -> if (!value.contains('\u0000')) lastId = value
            else -> Unit
        }
    }

    private fun dispatch() {
        if (!hasData) {
            eventName = null
            return
        }
        val event = SSEEvent(eventName, data.toString(), lastId)
        data.setLength(0)
        hasData = false
        eventName = null
        onEvent(event)
    }

    private companion object {
        const val LF: Byte = '\n'.code.toByte()
        const val CR: Byte = '\r'.code.toByte()
    }
}
