package com.kelpie.browser.automation

import java.io.ByteArrayOutputStream
import java.io.OutputStream
import kotlin.math.roundToLong

/** Native Android has no GIF writer. Fixed bounded RGB332 palette + GIF LZW. */
class ScriptGifEncoder(
    private val output: OutputStream,
    private val width: Int,
    private val height: Int,
    private val budget: ScriptMediaBudget,
    markerColor: Int,
) {
    private val marker = markerColor and 0xffffff
    private var started = false
    private var finished = false
    private var boundary = 0L
    var frameCount = 0
        private set
    var droppedFrames = 0
        private set
    val durationMs: Long get() = boundary * 10

    init {
        require(width in 1..4096 && height in 1..4096 && width.toLong() * height <= 8_388_608)
    }

    fun frame(
        pixels: IntArray,
        endMs: Double,
    ): Boolean {
        check(!finished)
        require(pixels.size == width * height && endMs.isFinite() && endMs >= 0)
        val next = (endMs / 10).roundToLong()
        if (next <= boundary) {
            droppedFrames++
            return true
        }
        val data = compress(pixels)
        val copies = (next - boundary + 65534) / 65535
        val imageBytes = 10L + 1 + data.size + (data.size + 254) / 255 + 1
        val needed = copies * (8 + imageBytes) + if (started) 0 else 13L + 768 + 19 + 1
        if (!budget.take(needed)) {
            droppedFrames++
            return false
        }
        if (!started) {
            output.write("GIF89a".toByteArray(Charsets.US_ASCII))
            word(width)
            word(height)
            output.write(byteArrayOf(0xf7.toByte(), 0, 0))
            for (index in 0..255) {
                val color =
                    when (index) {
                        255 -> marker
                        254 -> 0xffffff
                        else ->
                            (((index ushr 5) * 255 / 7) shl 16) or
                                ((((index ushr 2) and 7) * 255 / 7) shl 8) or ((index and 3) * 255 / 3)
                    }
                output.write((color ushr 16) and 255)
                output.write((color ushr 8) and 255)
                output.write(color and 255)
            }
            output.write(byteArrayOf(0x21, 0xff.toByte(), 11))
            output.write("NETSCAPE2.0".toByteArray(Charsets.US_ASCII))
            output.write(byteArrayOf(3, 1, 0, 0, 0))
            started = true
        }
        var remaining = next - boundary
        while (remaining > 0) {
            val delay = minOf(remaining, 65535).toInt()
            output.write(byteArrayOf(0x21, 0xf9.toByte(), 4, 4))
            word(delay)
            output.write(byteArrayOf(0, 0, 0x2c))
            word(0)
            word(0)
            word(width)
            word(height)
            output.write(0)
            output.write(8)
            var offset = 0
            while (offset < data.size) {
                val count = minOf(255, data.size - offset)
                output.write(count)
                output.write(data, offset, count)
                offset += count
            }
            output.write(0)
            remaining -= delay
            frameCount++
        }
        boundary = next
        output.flush()
        return true
    }

    fun finish() {
        if (finished) return
        finished = true
        if (started) output.write(0x3b)
        output.flush()
    }

    private fun word(value: Int) {
        output.write(value and 255)
        output.write((value ushr 8) and 255)
    }

    private fun index(pixel: Int): Int {
        val rgb = pixel and 0xffffff
        if (rgb == marker) return 255
        if (rgb == 0xffffff) return 254
        val value = ((rgb ushr 16) and 0xe0) or ((rgb ushr 11) and 0x1c) or ((rgb ushr 6) and 3)
        return if (value >= 254) 254 else value
    }

    private fun compress(pixels: IntArray): ByteArray {
        val writer = Codes()
        val dictionary = HashMap<Int, Int>(4096)
        var next = 258
        var width = 9
        writer.write(256, width)
        var prefix = index(pixels[0])
        for (position in 1 until pixels.size) {
            val color = index(pixels[position])
            val key = (prefix shl 8) or color
            val found = dictionary[key]
            if (found != null) {
                prefix = found
                continue
            }
            writer.write(prefix, width)
            if (next < 4096) {
                dictionary[key] = next++
                if (next > (1 shl width) && width < 12) width++
            } else {
                writer.write(256, width)
                dictionary.clear()
                next = 258
                width = 9
            }
            prefix = color
        }
        writer.write(prefix, width)
        if (next == (1 shl width) && width < 12) width++
        writer.write(257, width)
        return writer.finish()
    }

    private class Codes {
        private val bytes = ByteArrayOutputStream()
        private var bits = 0
        private var count = 0

        fun write(
            code: Int,
            width: Int,
        ) {
            bits = bits or (code shl count)
            count += width
            while (count >= 8) {
                bytes.write(bits and 255)
                bits = bits ushr 8
                count -= 8
            }
        }

        fun finish(): ByteArray {
            if (count > 0) bytes.write(bits and 255)
            return bytes.toByteArray()
        }
    }
}
