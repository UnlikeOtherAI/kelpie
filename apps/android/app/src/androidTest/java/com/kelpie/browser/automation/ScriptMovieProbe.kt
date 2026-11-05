@file:Suppress("DEPRECATION")

package com.kelpie.browser.automation

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Movie
import android.media.MediaExtractor
import android.media.MediaMetadataRetriever
import java.io.File
import java.nio.ByteBuffer

/** Independent native decoders inspect every encoded frame, not just a cover image. */
internal object ScriptMovieProbe {
    fun frames(
        file: File,
        visit: (Bitmap, Long) -> Unit,
    ) {
        if (file.extension == "gif") gif(file, visit) else video(file, visit)
    }

    private fun gif(
        file: File,
        visit: (Bitmap, Long) -> Unit,
    ) {
        val bytes = file.readBytes()
        val movie = checkNotNull(Movie.decodeByteArray(bytes, 0, bytes.size))
        val bitmap = Bitmap.createBitmap(movie.width(), movie.height(), Bitmap.Config.ARGB_8888)
        try {
            for (time in gifTimes(bytes)) {
                bitmap.eraseColor(android.graphics.Color.TRANSPARENT)
                movie.setTime((time + 1).toInt())
                movie.draw(Canvas(bitmap), 0f, 0f)
                visit(bitmap, time * 1000)
            }
        } finally {
            bitmap.recycle()
        }
    }

    private fun gifTimes(bytes: ByteArray): List<Long> {
        var at = 6

        fun octet(): Int = bytes[at++].toInt() and 255

        fun word(): Int = octet() or (octet() shl 8)

        fun blocks() {
            while (true) {
                val size = octet()
                if (size == 0) break
                at += size
            }
        }
        word()
        word()
        val packed = octet()
        octet()
        octet()
        if (packed and 128 != 0) at += 3 * (1 shl ((packed and 7) + 1))
        val times = mutableListOf<Long>()
        var elapsed = 0L
        var delay = 0
        while (at < bytes.size) {
            when (octet()) {
                0x21 ->
                    when (octet()) {
                        0xf9 -> {
                            check(octet() == 4)
                            octet()
                            delay = word()
                            octet()
                            check(octet() == 0)
                        }
                        else -> blocks()
                    }
                0x2c -> {
                    word()
                    word()
                    word()
                    word()
                    val local = octet()
                    if (local and 128 != 0) at += 3 * (1 shl ((local and 7) + 1))
                    octet()
                    blocks()
                    times += elapsed
                    elapsed += delay * 10L
                    delay = 0
                }
                0x3b -> return times
                else -> error("Invalid GIF block")
            }
        }
        error("Missing GIF trailer")
    }

    private fun video(
        file: File,
        visit: (Bitmap, Long) -> Unit,
    ) {
        val extractor = MediaExtractor()
        val decoder = MediaMetadataRetriever()
        try {
            extractor.setDataSource(file.absolutePath)
            extractor.selectTrack(0)
            decoder.setDataSource(file.absolutePath)
            val buffer = ByteBuffer.allocate(4_000_000)
            var prior = -1L
            while (extractor.readSampleData(buffer, 0) >= 0) {
                val timestamp = extractor.sampleTime
                check(timestamp > prior)
                prior = timestamp
                val bitmap = checkNotNull(decoder.getFrameAtTime(timestamp, MediaMetadataRetriever.OPTION_CLOSEST))
                try {
                    visit(bitmap, timestamp)
                } finally {
                    bitmap.recycle()
                }
                if (!extractor.advance()) break
            }
        } finally {
            extractor.release()
            decoder.release()
        }
    }
}
