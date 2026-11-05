package com.kelpie.browser.automation

import android.media.MediaCodec
import android.media.MediaCodecInfo
import android.media.MediaCodecList
import android.media.MediaFormat
import android.media.MediaMuxer
import java.io.File
import java.nio.ByteBuffer

/** Native H.264 only. Encoded samples are admitted before the MP4 muxer sees them. */
internal class ScriptVideoEncoder(
    private val width: Int,
    private val height: Int,
    fps: Int,
    private val budget: ScriptMediaBudget,
    private val diagnostics: ScriptCaptureDiagnostics? = null,
    private val createFile: () -> File,
) {
    private val codec: MediaCodec
    private var muxer: MediaMuxer? = null
    private var format: MediaFormat? = null
    private var outputFile: File? = null
    private var track = -1
    private var pending = 0
    private var submitted = 0
    val submittedFrames: Int get() = submitted
    private val pendingDocuments = mutableMapOf<Long, String>()
    var lastWrittenDocument: String? = null
        private set
    private var ended = false
    private var lastAcceptedUs = -1L
    val lastWrittenMs: Double get() = lastAcceptedUs / 1000.0
    var frames = 0
        private set
    var dropped = 0
        private set
    var durationMs = 0.0
        private set

    init {
        val requested = videoFormat(width, height, fps)
        val name =
            MediaCodecList(MediaCodecList.REGULAR_CODECS).findEncoderForFormat(requested)
                ?: throw ScriptFailure("CAPTURE_VIDEO_UNAVAILABLE")
        codec = MediaCodec.createByCodecName(name)
        try {
            codec.configure(requested, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
            codec.start()
        } catch (_: Exception) {
            codec.release()
            throw ScriptFailure("CAPTURE_VIDEO_UNAVAILABLE")
        }
    }

    fun frame(
        pixels: IntArray,
        elapsedMs: Double,
        documentId: String = "",
    ): Boolean {
        if (budget.exceeded) return false
        drain(false)
        if (pending >= 4) {
            dropped++
            return true
        }
        // start() does not promise an immediately available input buffer. Never
        // discard the sole initial frame merely because the codec is starting.
        val first = submitted == 0
        var index = codec.dequeueInputBuffer(if (first) 10_000 else 0)
        val deadline = System.nanoTime() + 1_000_000_000L
        while (first && index < 0 && System.nanoTime() < deadline) {
            drain(false)
            index = codec.dequeueInputBuffer(10_000)
        }
        if (index < 0) {
            if (first) throw ScriptFailure("CAPTURE_VIDEO_UNAVAILABLE")
            dropped++
            return true
        }
        val conversionStarted = System.nanoTime()
        val image = codec.getInputImage(index) ?: throw ScriptFailure("CAPTURE_VIDEO_UNAVAILABLE")
        try {
            val planes = image.planes
            ScriptYuv420.convert(
                pixels,
                width,
                height,
                ScriptYuv420.Plane(planes[0].buffer, planes[0].rowStride, planes[0].pixelStride),
                ScriptYuv420.Plane(planes[1].buffer, planes[1].rowStride, planes[1].pixelStride),
                ScriptYuv420.Plane(planes[2].buffer, planes[2].rowStride, planes[2].pixelStride),
            )
        } finally {
            image.close()
            diagnostics?.record(ScriptCaptureDiagnostics.Phase.VIDEO_CONVERSION, System.nanoTime() - conversionStarted)
        }
        val timestamp = (elapsedMs * 1000).toLong()
        val submitStarted = System.nanoTime()
        codec.queueInputBuffer(index, 0, width * height * 3 / 2, timestamp, 0)
        diagnostics?.record(ScriptCaptureDiagnostics.Phase.VIDEO_SUBMIT, System.nanoTime() - submitStarted)
        pendingDocuments[timestamp] = documentId
        pending++
        submitted++
        drain(false)
        return !budget.exceeded
    }

    fun finish(terminalMs: Double): File? {
        try {
            val deadline = System.nanoTime() + 5_000_000_000L
            var index = -1
            while (index < 0 && System.nanoTime() < deadline) {
                drain(false)
                index = codec.dequeueInputBuffer(10_000)
            }
            if (index < 0) throw ScriptFailure("CAPTURE_ENCODING_TIMEOUT")
            val terminalUs = maxOf((terminalMs * 1000).toLong(), lastAcceptedUs + 1)
            codec.queueInputBuffer(index, 0, 0, terminalUs, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
            drain(true)
            if (muxer != null && frames > 0) {
                val end =
                    MediaCodec.BufferInfo().apply {
                        set(0, 0, terminalUs, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                    }
                muxer?.writeSampleData(track, ByteBuffer.allocate(0), end)
                durationMs = terminalUs / 1000.0
                muxer?.stop()
            }
            if (frames == 0 && !budget.exceeded) throw ScriptFailure("CAPTURE_ENCODING_EMPTY")
            return outputFile?.takeIf { frames > 0 }
        } finally {
            runCatching { muxer?.release() }
            runCatching { codec.stop() }
            codec.release()
        }
    }

    private fun drain(final: Boolean) {
        val started = System.nanoTime()
        try {
            drainCodec(final)
        } finally {
            diagnostics?.record(ScriptCaptureDiagnostics.Phase.VIDEO_DRAIN, System.nanoTime() - started)
        }
    }

    private fun drainCodec(final: Boolean) {
        val deadline = System.nanoTime() + 5_000_000_000L
        while (!ended) {
            val info = MediaCodec.BufferInfo()
            val index = codec.dequeueOutputBuffer(info, if (final) 10_000 else 0)
            if (index == MediaCodec.INFO_TRY_AGAIN_LATER) {
                if (!final) return
                if (System.nanoTime() >= deadline) throw ScriptFailure("CAPTURE_ENCODING_TIMEOUT")
                continue
            }
            if (index == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
                format = codec.outputFormat
                continue
            }
            if (index < 0) continue
            try {
                if (info.size > 0 && info.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG == 0) {
                    pending = maxOf(pending - 1, 0)
                    val document =
                        pendingDocuments.remove(info.presentationTimeUs)
                            ?: throw ScriptFailure("CAPTURE_INVALID_TIMESTAMP")
                    val bytes = info.size.toLong() * 2 + 512 + if (frames == 0) 65_536 else 0
                    if (!budget.take(bytes)) {
                        dropped++
                    } else {
                        if (info.presentationTimeUs <= lastAcceptedUs) throw ScriptFailure("CAPTURE_INVALID_TIMESTAMP")
                        if (muxer == null) {
                            val destination = createFile()
                            val created = MediaMuxer(destination.absolutePath, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
                            try {
                                track = created.addTrack(format ?: throw ScriptFailure("CAPTURE_VIDEO_UNAVAILABLE"))
                                created.start()
                            } catch (error: Exception) {
                                created.release()
                                throw error
                            }
                            muxer = created
                            outputFile = destination
                        }
                        val buffer = codec.getOutputBuffer(index) ?: throw ScriptFailure("CAPTURE_ENCODING_FAILED")
                        muxer?.writeSampleData(track, buffer, info)
                        lastAcceptedUs = info.presentationTimeUs
                        lastWrittenDocument = document
                        frames++
                    }
                }
                ended = info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0
            } finally {
                codec.releaseOutputBuffer(index, false)
            }
        }
    }

    companion object {
        fun available(): Boolean =
            MediaCodecList(MediaCodecList.REGULAR_CODECS).codecInfos.any {
                it.isEncoder && it.supportedTypes.any { type -> type.equals(MediaFormat.MIMETYPE_VIDEO_AVC, true) }
            }

        private fun videoFormat(
            width: Int,
            height: Int,
            fps: Int,
        ): MediaFormat =
            MediaFormat.createVideoFormat(MediaFormat.MIMETYPE_VIDEO_AVC, width, height).apply {
                setInteger(MediaFormat.KEY_COLOR_FORMAT, MediaCodecInfo.CodecCapabilities.COLOR_FormatYUV420Flexible)
                setInteger(MediaFormat.KEY_BIT_RATE, (width.toLong() * height * fps / 8).coerceIn(256_000, 12_000_000).toInt())
                setInteger(MediaFormat.KEY_FRAME_RATE, fps)
                setInteger(MediaFormat.KEY_I_FRAME_INTERVAL, 1)
                setInteger(MediaFormat.KEY_PROFILE, MediaCodecInfo.CodecProfileLevel.AVCProfileBaseline)
                setInteger(MediaFormat.KEY_COLOR_STANDARD, MediaFormat.COLOR_STANDARD_BT601_NTSC)
                setInteger(MediaFormat.KEY_COLOR_RANGE, MediaFormat.COLOR_RANGE_LIMITED)
                setInteger(MediaFormat.KEY_COLOR_TRANSFER, MediaFormat.COLOR_TRANSFER_SDR_VIDEO)
            }
    }
}
