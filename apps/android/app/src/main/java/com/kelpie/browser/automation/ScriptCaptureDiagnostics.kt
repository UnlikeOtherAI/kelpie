package com.kelpie.browser.automation

import android.util.Log
import com.kelpie.browser.BuildConfig

/** Numeric, bounded diagnostics for compositor and encoder bottlenecks in debug builds. */
internal class ScriptCaptureDiagnostics {
    enum class Phase { VISUAL, COMMIT, PIXEL_COPY, QUEUE, ENCODE }

    private data class Sample(
        var count: Long = 0,
        var total: Long = 0,
        var maximum: Long = 0,
    )

    private val samples = Array(Phase.entries.size) { Sample() }

    @Synchronized
    fun record(
        phase: Phase,
        nanos: Long,
    ) {
        if (!BuildConfig.DEBUG || nanos < 0) return
        val sample = samples[phase.ordinal]
        sample.count++
        sample.total += nanos
        sample.maximum = maxOf(sample.maximum, nanos)
    }

    @Synchronized
    fun report() {
        if (!BuildConfig.DEBUG) return
        for (phase in Phase.entries) {
            val sample = samples[phase.ordinal]
            Log.d("KelpieCaptureTiming", "phase=${phase.name} count=${sample.count} totalNs=${sample.total} maxNs=${sample.maximum}")
        }
    }
}
