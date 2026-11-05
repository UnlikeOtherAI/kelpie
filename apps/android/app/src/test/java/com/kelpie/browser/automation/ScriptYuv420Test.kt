package com.kelpie.browser.automation

import org.junit.Assert.assertArrayEquals
import org.junit.Test
import java.nio.ByteBuffer
import java.util.Random

class ScriptYuv420Test {
    @Test
    fun fusedConversionMatchesOriginalForPaddedAndInterleavedPlanes() {
        val random = Random(8192)
        for ((width, height) in listOf(2 to 2, 8 to 6, 32 to 18)) {
            val pixels = IntArray(width * height) { random.nextInt() }
            for (chromaStride in listOf(1, 2)) {
                val yStride = width + 7
                val uvStride = width * chromaStride / 2 + 5

                fun buffer(size: Int): ByteBuffer = ByteBuffer.allocate(size + 11).apply { position(3) }
                val actual = listOf(buffer(yStride * height), buffer(uvStride * height), buffer(uvStride * height))
                val expected = listOf(buffer(yStride * height), buffer(uvStride * height), buffer(uvStride * height))

                fun put(
                    buffer: ByteBuffer,
                    row: Int,
                    stride: Int,
                    x: Int,
                    y: Int,
                    value: Int,
                ) {
                    buffer.put(buffer.position() + y * row + x * stride, value.coerceIn(0, 255).toByte())
                }
                for (y in 0 until height) {
                    for (x in 0 until width) {
                        val pixel = pixels[y * width + x]
                        val r = (pixel ushr 16) and 255
                        val g = (pixel ushr 8) and 255
                        val b = pixel and 255
                        put(expected[0], yStride, 1, x, y, ((66 * r + 129 * g + 25 * b + 128) shr 8) + 16)
                    }
                }
                for (y in 0 until height step 2) {
                    for (x in 0 until width step 2) {
                        var r = 0
                        var g = 0
                        var b = 0
                        for (dy in 0..1) {
                            for (dx in 0..1) {
                                val pixel = pixels[(y + dy) * width + x + dx]
                                r += (pixel ushr 16) and 255
                                g += (pixel ushr 8) and 255
                                b += pixel and 255
                            }
                        }
                        r = (r + 2) / 4
                        g = (g + 2) / 4
                        b = (b + 2) / 4
                        put(expected[1], uvStride, chromaStride, x / 2, y / 2, ((-38 * r - 74 * g + 112 * b + 128) shr 8) + 128)
                        put(expected[2], uvStride, chromaStride, x / 2, y / 2, ((112 * r - 94 * g - 18 * b + 128) shr 8) + 128)
                    }
                }
                ScriptYuv420.convert(
                    pixels,
                    width,
                    height,
                    ScriptYuv420.Plane(actual[0], yStride, 1),
                    ScriptYuv420.Plane(actual[1], uvStride, chromaStride),
                    ScriptYuv420.Plane(actual[2], uvStride, chromaStride),
                )
                for (i in actual.indices) assertArrayEquals(expected[i].array(), actual[i].array())
            }
        }
    }

    @Test
    fun directPlanesCanShareInterleavedStorageWithDistinctPositions() {
        val y = ByteBuffer.allocateDirect(64).apply { position(5) }
        val shared = ByteBuffer.allocateDirect(64)
        val u = shared.duplicate().apply { position(7) }
        val v = shared.duplicate().apply { position(8) }
        val pixels =
            intArrayOf(
                0xff000000.toInt(),
                0xffffffff.toInt(),
                0xffff0000.toInt(),
                0xff00ff00.toInt(),
                0xff0000ff.toInt(),
                0xff202020.toInt(),
                0xff808080.toInt(),
                0xffabcdef.toInt(),
            )
        ScriptYuv420.convert(
            pixels,
            4,
            2,
            ScriptYuv420.Plane(y, 9, 1),
            ScriptYuv420.Plane(u, 11, 2),
            ScriptYuv420.Plane(v, 11, 2),
        )
        for (row in 0..1) {
            for (column in 0..3) {
                val p = pixels[row * 4 + column]
                val r = (p ushr 16) and 255
                val g = (p ushr 8) and 255
                val b = p and 255
                val expected = (((66 * r + 129 * g + 25 * b + 128) shr 8) + 16).coerceIn(0, 255)
                org.junit.Assert.assertEquals(expected, y.get(5 + row * 9 + column).toInt() and 255)
            }
        }
        for (column in 0..1) {
            val group = listOf(pixels[column * 2], pixels[column * 2 + 1], pixels[4 + column * 2], pixels[5 + column * 2])
            val r = (group.sumOf { (it ushr 16) and 255 } + 2) / 4
            val g = (group.sumOf { (it ushr 8) and 255 } + 2) / 4
            val b = (group.sumOf { it and 255 } + 2) / 4
            val expectedU = (((-38 * r - 74 * g + 112 * b + 128) shr 8) + 128).coerceIn(0, 255)
            val expectedV = (((112 * r - 94 * g - 18 * b + 128) shr 8) + 128).coerceIn(0, 255)
            org.junit.Assert.assertEquals(expectedU, shared.get(7 + column * 2).toInt() and 255)
            org.junit.Assert.assertEquals(expectedV, shared.get(8 + column * 2).toInt() and 255)
        }
    }
}
