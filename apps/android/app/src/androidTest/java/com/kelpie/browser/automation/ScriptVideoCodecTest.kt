package com.kelpie.browser.automation

import android.graphics.Color
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.MediaMetadataRetriever
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File
import java.nio.ByteBuffer
import java.util.UUID

/** Native encode and independent Android extractor/decoder, including chroma. */
@RunWith(AndroidJUnit4::class)
class ScriptVideoCodecTest {
    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext

    @Test
    fun h264DecodesColorsDimensionsTimingAndPlayableEarlyStop() {
        assertTrue("Native AVC encoder unavailable", ScriptVideoEncoder.available())
        for (count in listOf(2, 4)) {
            val width = if (count == 2) 64 else 78
            val height = if (count == 2) 48 else 50
            val prefix = "rgb-" + width + "x" + height + "-" + UUID.randomUUID()
            val evidence = File(context.getExternalFilesDir(null), "script-codec-acceptance").apply { mkdirs() }
            val directory = File(context.cacheDir, "codec-" + UUID.randomUUID()).apply { mkdir() }
            try {
                val budget = ScriptMediaBudget(2_000_000)
                val encoder =
                    ScriptVideoEncoder(width, height, 10, budget) {
                        File.createTempFile("owned-", ".mp4", directory)
                    }
                val colors = intArrayOf(Color.RED, Color.GREEN, Color.BLUE, Color.WHITE)
                repeat(count) { index ->
                    assertTrue(encoder.frame(IntArray(width * height) { colors[index] }, index * 100.0, "document-" + index))
                    Thread.sleep(40)
                }
                val file = checkNotNull(encoder.finish(count * 100.0))
                file.copyTo(File(evidence, prefix + ".mp4"))
                assertEquals(count, encoder.frames)
                assertEquals("document-" + (count - 1), encoder.lastWrittenDocument)
                assertTrue(file.length() > 0)
                assertTrue(file.length() <= budget.limit)
                assertEquals(count * 100.0, encoder.durationMs, 1.0)
                val extractor = MediaExtractor()
                try {
                    extractor.setDataSource(file.absolutePath)
                    val format = extractor.getTrackFormat(0)
                    assertEquals(MediaFormat.MIMETYPE_VIDEO_AVC, format.getString(MediaFormat.KEY_MIME))
                    assertEquals(width, format.getInteger(MediaFormat.KEY_WIDTH))
                    assertEquals(height, format.getInteger(MediaFormat.KEY_HEIGHT))
                    extractor.selectTrack(0)
                    var samples = 0
                    var previous = -1L
                    val encoded = ByteBuffer.allocate(128_000)
                    while (extractor.readSampleData(encoded, 0) >= 0) {
                        val timestamp = extractor.sampleTime
                        assertTrue(timestamp > previous)
                        previous = timestamp
                        samples++
                        if (!extractor.advance()) break
                    }
                    assertEquals(count, samples)
                } finally {
                    extractor.release()
                }
                val decoder = MediaMetadataRetriever()
                try {
                    decoder.setDataSource(file.absolutePath)
                    val duration = checkNotNull(decoder.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)).toLong()
                    assertEquals(count * 100.0, duration.toDouble(), 25.0)
                    repeat(count) { index ->
                        val bitmap = decoder.getFrameAtTime(index * 100_000L, MediaMetadataRetriever.OPTION_CLOSEST)
                        assertNotNull(bitmap)
                        checkNotNull(bitmap)
                        assertEquals(width, bitmap.width)
                        assertEquals(height, bitmap.height)
                        File(evidence, prefix + "-frame-" + index + ".png").outputStream().use {
                            bitmap.compress(android.graphics.Bitmap.CompressFormat.PNG, 100, it)
                        }
                        val expected = colors[index]
                        for ((x, y) in listOf(width / 2 to height / 2, 4 to 4, width - 4 to height - 4)) {
                            val actual = bitmap.getPixel(x, y)
                            assertTrue("Red channel at frame " + index, kotlin.math.abs(Color.red(actual) - Color.red(expected)) < 45)
                            assertTrue("Green channel at frame " + index, kotlin.math.abs(Color.green(actual) - Color.green(expected)) < 45)
                            assertTrue("Blue channel at frame " + index, kotlin.math.abs(Color.blue(actual) - Color.blue(expected)) < 45)
                        }
                        bitmap.recycle()
                    }
                } finally {
                    decoder.release()
                }
            } finally {
                directory.listFiles()?.forEach { it.delete() }
                directory.delete()
            }
        }
    }

    @Test
    fun minimumBudgetRefusesVideoWithoutPublishingInvalidFile() {
        val directory = File(context.cacheDir, "budget-" + UUID.randomUUID()).apply { mkdir() }
        try {
            val budget = ScriptMediaBudget(1024)
            val encoder = ScriptVideoEncoder(64, 48, 10, budget) { File.createTempFile("owned-", ".mp4", directory) }
            encoder.frame(IntArray(64 * 48) { Color.RED }, 0.0)
            assertEquals("Sole initial frame must be submitted, not dropped during startup", 1, encoder.submittedFrames)
            val result = encoder.finish(100.0)
            assertEquals(null, result)
            assertTrue(budget.exceeded)
            assertEquals(0, directory.listFiles().orEmpty().size)
        } finally {
            directory.listFiles()?.forEach { it.delete() }
            directory.delete()
        }
    }
}
