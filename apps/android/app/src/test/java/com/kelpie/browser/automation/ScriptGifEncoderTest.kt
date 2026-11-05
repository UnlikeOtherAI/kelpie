package com.kelpie.browser.automation

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.w3c.dom.Element
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.util.Random

class ScriptGifEncoderTest {
    // Android's compile classpath omits desktop ImageIO; use only its exported
    // JDK interfaces reflectively so the decoder remains independent of ours.
    private class DecodedImage(
        private val image: Any,
    ) {
        private val type = Class.forName("java.awt.image.BufferedImage")
        val width: Int get() = type.getMethod("getWidth").invoke(image) as Int
        val height: Int get() = type.getMethod("getHeight").invoke(image) as Int

        fun getRGB(
            x: Int,
            y: Int,
        ): Int = type.getMethod("getRGB", Int::class.javaPrimitiveType, Int::class.javaPrimitiveType).invoke(image, x, y) as Int
    }

    private fun decode(bytes: ByteArray): List<Pair<DecodedImage, Int>> {
        val imageIO = Class.forName("javax.imageio.ImageIO")
        val readerType = Class.forName("javax.imageio.ImageReader")
        val metadataType = Class.forName("javax.imageio.metadata.IIOMetadata")
        val readers = imageIO.getMethod("getImageReadersByFormatName", String::class.java).invoke(null, "gif") as Iterator<*>
        val reader = checkNotNull(readers.next())
        val input = imageIO.getMethod("createImageInputStream", Any::class.java).invoke(null, ByteArrayInputStream(bytes))
        return (input as java.io.Closeable).use {
            readerType.getMethod("setInput", Any::class.java).invoke(reader, input)
            try {
                val count = readerType.getMethod("getNumImages", Boolean::class.javaPrimitiveType).invoke(reader, true) as Int
                (0 until count).map { index ->
                    val metadata = readerType.getMethod("getImageMetadata", Int::class.javaPrimitiveType).invoke(reader, index)
                    val tree = metadataType.getMethod("getAsTree", String::class.java).invoke(metadata, "javax_imageio_gif_image_1.0") as Element
                    val delay =
                        tree
                            .getElementsByTagName("GraphicControlExtension")
                            .item(0)
                            .attributes
                            .getNamedItem("delayTime")
                            .nodeValue
                            .toInt()
                    val image = readerType.getMethod("read", Int::class.javaPrimitiveType).invoke(reader, index)
                    DecodedImage(checkNotNull(image)) to delay
                }
            } finally {
                readerType.getMethod("dispose").invoke(reader)
            }
        }
    }

    @Test
    fun decodesDictionaryGrowthAndResetsWithChangingPixels() {
        val output = ByteArrayOutputStream()
        val encoder = ScriptGifEncoder(output, 128, 96, ScriptMediaBudget(2_000_000), 0xff3b82f6.toInt())
        val random = Random(42)
        repeat(3) { index ->
            val pixels = IntArray(128 * 96) { random.nextInt() or 0xff000000.toInt() }
            assertTrue(encoder.frame(pixels, (index + 1) * 137.0))
        }
        encoder.finish()
        val frames = decode(output.toByteArray())
        assertEquals(3, frames.size)
        assertEquals(410, frames.sumOf { it.second } * 10)
        assertEquals(128, frames[0].first.width)
        assertEquals(96, frames[2].first.height)
        assertFalse(frames[0].first.getRGB(40, 50) == frames[1].first.getRGB(40, 50))
    }

    @Test
    fun randomFramePreservesEveryQuantizedPixelAcrossDictionaryResets() {
        val random = Random(314159)
        val pixels = IntArray(256 * 256) { random.nextInt() or 0xff000000.toInt() }
        val output = ByteArrayOutputStream()
        val encoder = ScriptGifEncoder(output, 256, 256, ScriptMediaBudget(2_000_000), 0xff3b82f6.toInt())
        assertTrue(encoder.frame(pixels, 100.0))
        encoder.finish()
        val image = decode(output.toByteArray()).single().first
        pixels.forEachIndexed { index, pixel ->
            val rgb = pixel and 0xffffff
            val paletteIndex = ((rgb ushr 16) and 0xe0) or ((rgb ushr 11) and 0x1c) or ((rgb ushr 6) and 3)
            val expected =
                when {
                    rgb == 0x3b82f6 -> 0xff3b82f6.toInt()
                    rgb == 0xffffff || paletteIndex >= 254 -> 0xffffffff.toInt()
                    else ->
                        (0xff000000.toInt()) or (((paletteIndex ushr 5) * 255 / 7) shl 16) or
                            ((((paletteIndex ushr 2) and 7) * 255 / 7) shl 8) or ((paletteIndex and 3) * 255 / 3)
                }
            assertEquals("pixel " + index, expected, image.getRGB(index % 256, index / 256))
        }
    }

    @Test
    fun preservesRequestedMarkerColorAndLoops() {
        val color = 0xff3b82f6.toInt()
        val output = ByteArrayOutputStream()
        val encoder = ScriptGifEncoder(output, 16, 16, ScriptMediaBudget(20_000), color)
        assertTrue(encoder.frame(IntArray(256) { color }, 50.0))
        assertTrue(encoder.frame(IntArray(256) { 0xffffffff.toInt() }, 100.0))
        encoder.finish()
        val frames = decode(output.toByteArray())
        assertEquals(color, frames[0].first.getRGB(8, 8))
        assertEquals(0xffffffff.toInt(), frames[1].first.getRGB(8, 8))
        assertTrue(String(output.toByteArray(), Charsets.ISO_8859_1).contains("NETSCAPE2.0"))
    }

    @Test
    fun cumulativeRoundingPreservesWallTimeAndLongHolds() {
        val output = ByteArrayOutputStream()
        val encoder = ScriptGifEncoder(output, 16, 16, ScriptMediaBudget(100_000), 0xff0000)
        repeat(60) { assertTrue(encoder.frame(IntArray(256), (it + 1) * 1000.0 / 60)) }
        encoder.finish()
        assertEquals(1000, decode(output.toByteArray()).sumOf { it.second } * 10)
        val held = ByteArrayOutputStream()
        val long = ScriptGifEncoder(held, 16, 16, ScriptMediaBudget(10_000), 0xff0000)
        long.frame(IntArray(256), 700_000.0)
        long.finish()
        val frames = decode(held.toByteArray())
        assertEquals(2, frames.size)
        assertEquals(700_000, frames.sumOf { it.second } * 10)
    }

    @Test
    fun independentDecoderRecoversEveryPixelAcrossCodeWidths() {
        val colors =
            intArrayOf(
                0xff000000.toInt(),
                0xffff0000.toInt(),
                0xff00ff00.toInt(),
                0xff0000ff.toInt(),
                0xffffff00.toInt(),
                0xffff00ff.toInt(),
                0xff00ffff.toInt(),
                0xffffffff.toInt(),
            )
        for (size in listOf(257, 511, 512, 513, 1024, 2048, 4096)) {
            val random = Random(size.toLong())
            val pixels = IntArray(size) { colors[random.nextInt(colors.size)] }
            val output = ByteArrayOutputStream()
            val encoder = ScriptGifEncoder(output, 1, size, ScriptMediaBudget(100_000), 0xff3b82f6.toInt())
            encoder.frame(pixels, 100.0)
            encoder.finish()
            val image = decode(output.toByteArray()).single().first
            for (row in pixels.indices) assertEquals("LZW pixel at row " + row, pixels[row], image.getRGB(0, row))
        }
    }

    @Test
    fun budgetStopLeavesDecodablePartialAndDoesNotClampMinimum() {
        val output = ByteArrayOutputStream()
        val budget = ScriptMediaBudget(1024)
        val encoder = ScriptGifEncoder(output, 16, 16, budget, 0xff0000)
        assertTrue(encoder.frame(IntArray(256), 40.0))
        var accepted = true
        var count = 1
        while (accepted && count < 100) {
            count++
            accepted = encoder.frame(IntArray(256) { if (it % 2 == 0) 0xff0000 else 0xffffff }, count * 40.0)
        }
        assertFalse(accepted)
        assertTrue(budget.exceeded)
        encoder.finish()
        assertTrue(output.size() <= 1024)
        assertEquals(encoder.frameCount, decode(output.toByteArray()).size)
        assertTrue(encoder.droppedFrames > 0)
    }
}
