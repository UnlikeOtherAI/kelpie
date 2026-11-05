package com.kelpie.browser.automation

/** Admission precedes writes; reservations include codec/container finalization. */
class ScriptMediaBudget(
    val limit: Long,
) {
    init {
        require(limit in 1024L..268_435_456L)
    }

    private var reserved = 0L
    var exceeded: Boolean = false
        private set

    @Synchronized
    fun take(bytes: Long): Boolean {
        require(bytes >= 0)
        if (exceeded || bytes > limit - reserved) {
            exceeded = true
            return false
        }
        reserved += bytes
        return true
    }
}
