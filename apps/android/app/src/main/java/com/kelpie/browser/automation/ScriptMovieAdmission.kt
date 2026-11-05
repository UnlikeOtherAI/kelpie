package com.kelpie.browser.automation

/** Actual encoded-frame acknowledgements; a queued or dropped frame never qualifies. */
class ScriptMovieAdmission(
    formats: List<String>,
) {
    private data class Sample(
        val absoluteMs: Double,
        val documentId: String,
    )

    private val samples =
        mutableMapOf<String, Sample?>().apply {
            for (format in formats) if (format == "gif" || format == "video") put(format, null)
        }

    fun enabled(): Boolean = samples.isNotEmpty()

    @Synchronized
    fun admit(
        format: String,
        absoluteMs: Double,
        documentId: String,
    ) {
        if (format in samples && absoluteMs.isFinite() && absoluteMs >= 0) {
            val prior = samples[format]
            if (prior == null || absoluteMs > prior.absoluteMs) samples[format] = Sample(absoluteMs, documentId)
        }
    }

    @Synchronized
    fun contains(
        absoluteMs: Double,
        documentId: String,
    ): Boolean = samples.isNotEmpty() && samples.values.all { it != null && it.absoluteMs >= absoluteMs && it.documentId == documentId }
}
