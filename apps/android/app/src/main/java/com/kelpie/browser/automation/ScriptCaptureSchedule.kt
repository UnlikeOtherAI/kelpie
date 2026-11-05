package com.kelpie.browser.automation

/** Advances the original cadence past missed slots without adding another full interval. */
internal object ScriptCaptureSchedule {
    data class Advance(
        val next: Long,
        val missed: Long,
        val oldPolicyExcess: Long,
    )

    fun advance(
        previous: Long,
        now: Long,
        period: Long,
    ): Advance {
        require(period > 0)
        val scheduled = previous + period
        val missed = if (now >= scheduled) (now - scheduled) / period + 1 else 0
        val next = scheduled + missed * period
        val excess = if (missed > 0) now + period - next else 0
        return Advance(next, missed, excess)
    }
}
