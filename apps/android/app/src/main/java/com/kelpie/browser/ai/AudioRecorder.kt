package com.kelpie.browser.ai

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import android.os.SystemClock
import androidx.core.content.ContextCompat
import java.io.ByteArrayOutputStream
import java.nio.ByteBuffer
import java.nio.ByteOrder
import kotlin.concurrent.thread

class AudioRecorder(private val context: Context) {
    companion object {
        private const val SAMPLE_RATE = 16_000
        private const val CHANNEL_CONFIG = AudioFormat.CHANNEL_IN_MONO
        private const val AUDIO_FORMAT = AudioFormat.ENCODING_PCM_16BIT
        private const val MAX_DURATION_MS = 30_000L
    }

    data class Result(val audio: ByteArray, val durationMs: Int)

    @Volatile
    var isRecording: Boolean = false
        private set

    private var startedAtMs: Long = 0
    private var audioRecord: AudioRecord? = null
    private var recordThread: Thread? = null
    private var pcmBuffer = ByteArrayOutputStream()
    private var lastDurationMs: Int = 0
    @Volatile
    private var completedResult: Result? = null

    val elapsedMs: Int
        get() {
            if (isRecording) {
                return (SystemClock.elapsedRealtime() - startedAtMs).toInt()
            }
            return lastDurationMs
        }

    fun start() {
        if (isRecording) throw IllegalStateException("RECORDING_ALREADY_ACTIVE")

        if (ContextCompat.checkSelfPermission(context, Manifest.permission.RECORD_AUDIO)
            != PackageManager.PERMISSION_GRANTED
        ) {
            throw SecurityException("MIC_PERMISSION_DENIED")
        }

        val bufferSize = AudioRecord.getMinBufferSize(SAMPLE_RATE, CHANNEL_CONFIG, AUDIO_FORMAT)
            .coerceAtLeast(4096)

        @Suppress("MissingPermission")
        val recorder = AudioRecord(
            MediaRecorder.AudioSource.MIC,
            SAMPLE_RATE,
            CHANNEL_CONFIG,
            AUDIO_FORMAT,
            bufferSize,
        )

        if (recorder.state != AudioRecord.STATE_INITIALIZED) {
            recorder.release()
            throw IllegalStateException("RECORDING_FAILED: AudioRecord initialization failed")
        }

        pcmBuffer.reset()
        lastDurationMs = 0
        completedResult = null
        startedAtMs = SystemClock.elapsedRealtime()
        audioRecord = recorder
        isRecording = true

        recorder.startRecording()

        recordThread = thread(name = "kelpie-audio-record") {
            val buffer = ByteArray(bufferSize)
            while (isRecording) {
                if (SystemClock.elapsedRealtime() - startedAtMs >= MAX_DURATION_MS) {
                    break
                }
                val read = recorder.read(buffer, 0, buffer.size)
                if (read > 0) {
                    synchronized(pcmBuffer) {
                        pcmBuffer.write(buffer, 0, read)
                    }
                }
            }
            // Auto-stop if we hit max duration
            if (isRecording) {
                finalize()
            }
        }
    }

    fun stop(): Result {
        // If auto-stop already finalized, return that result
        completedResult?.let {
            completedResult = null
            return it
        }
        if (!isRecording) throw IllegalStateException("NO_RECORDING_ACTIVE")
        return finalize()
    }

    @Synchronized
    private fun finalize(): Result {
        // Guard against double-finalize from auto-stop + explicit stop race
        completedResult?.let { return it }

        isRecording = false
        lastDurationMs = (SystemClock.elapsedRealtime() - startedAtMs).toInt()

        audioRecord?.stop()
        audioRecord?.release()
        audioRecord = null
        recordThread = null

        val pcmData: ByteArray
        synchronized(pcmBuffer) {
            pcmData = pcmBuffer.toByteArray()
            pcmBuffer.reset()
        }

        val wavData = makeWav(pcmData)
        val result = Result(audio = wavData, durationMs = lastDurationMs)
        completedResult = result
        return result
    }

    private fun makeWav(pcm: ByteArray): ByteArray {
        val dataSize = pcm.size
        val byteRate = SAMPLE_RATE * 1 * 16 / 8  // sampleRate * channels * bitsPerSample / 8
        val blockAlign = 1 * 16 / 8               // channels * bitsPerSample / 8

        val header = ByteBuffer.allocate(44).order(ByteOrder.LITTLE_ENDIAN).apply {
            // RIFF header
            put("RIFF".toByteArray(Charsets.US_ASCII))
            putInt(36 + dataSize)
            put("WAVE".toByteArray(Charsets.US_ASCII))
            // fmt sub-chunk
            put("fmt ".toByteArray(Charsets.US_ASCII))
            putInt(16)             // sub-chunk size
            putShort(1)            // PCM format
            putShort(1)            // mono
            putInt(SAMPLE_RATE)    // sample rate
            putInt(byteRate)       // byte rate
            putShort(blockAlign.toShort()) // block align
            putShort(16)           // bits per sample
            // data sub-chunk
            put("data".toByteArray(Charsets.US_ASCII))
            putInt(dataSize)
        }

        return header.array() + pcm
    }
}
