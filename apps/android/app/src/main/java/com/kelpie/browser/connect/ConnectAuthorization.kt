package com.kelpie.browser.connect

import java.time.Instant

/** Immutable command authority cannot be borrowed by a later attempt on the same tab. */
data class ConnectAuthorization(
    val jobId: String,
    val attemptId: String,
    val deadline: Instant,
) {
    fun matches(
        current: Map<String, Any?>?,
        now: Instant = Instant.now(),
    ): Boolean = current?.get("jobId") == jobId && current?.get("attemptId") == attemptId && deadline > now

    companion object {
        fun from(command: Map<String, Any?>): ConnectAuthorization? =
            runCatching {
                ConnectAuthorization(
                    command["jobId"] as String,
                    command["attemptId"] as String,
                    Instant.parse(command["deadline"] as String),
                )
            }.getOrNull()
    }
}
