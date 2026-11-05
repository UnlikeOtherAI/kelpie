package com.kelpie.browser.automation

import java.nio.ByteBuffer

/** Converts ARGB pixels to the codec's flexible, limited-range BT.601 planes. */
internal object ScriptYuv420 {
    internal data class Plane(
        val buffer: ByteBuffer,
        val rowStride: Int,
        val pixelStride: Int,
    )

    fun convert(
        pixels: IntArray,
        width: Int,
        height: Int,
        yPlane: Plane,
        uPlane: Plane,
        vPlane: Plane,
    ) {
        require(width > 0 && height > 0 && width % 2 == 0 && height % 2 == 0 && pixels.size >= width * height)
        for (y in 0 until height step 2) {
            for (x in 0 until width step 2) {
                var redSum = 0
                var greenSum = 0
                var blueSum = 0
                for (dy in 0..1) {
                    for (dx in 0..1) {
                        val pixel = pixels[(y + dy) * width + x + dx]
                        val red = (pixel ushr 16) and 255
                        val green = (pixel ushr 8) and 255
                        val blue = pixel and 255
                        redSum += red
                        greenSum += green
                        blueSum += blue
                        put(yPlane, x + dx, y + dy, ((66 * red + 129 * green + 25 * blue + 128) shr 8) + 16)
                    }
                }
                val red = (redSum + 2) / 4
                val green = (greenSum + 2) / 4
                val blue = (blueSum + 2) / 4
                put(uPlane, x / 2, y / 2, ((-38 * red - 74 * green + 112 * blue + 128) shr 8) + 128)
                put(vPlane, x / 2, y / 2, ((112 * red - 94 * green - 18 * blue + 128) shr 8) + 128)
            }
        }
    }

    private fun put(
        plane: Plane,
        x: Int,
        y: Int,
        value: Int,
    ) {
        plane.buffer.put(
            plane.buffer.position() + y * plane.rowStride + x * plane.pixelStride,
            value.coerceIn(0, 255).toByte(),
        )
    }
}
