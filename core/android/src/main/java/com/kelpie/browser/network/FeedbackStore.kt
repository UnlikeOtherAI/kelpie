package com.kelpie.browser.network

import android.content.Context
import org.json.JSONObject
import java.io.File
import java.time.Instant
import java.util.UUID

data class FeedbackRecord(
    val reportId: String,
    val storedAt: String,
    val payload: Map<String, Any?>,
)

object FeedbackStore {
    fun save(
        context: Context,
        body: Map<String, Any?>,
        platform: String,
        deviceId: String,
        deviceName: String,
    ): FeedbackRecord {
        val reportId = UUID.randomUUID().toString().lowercase()
        val storedAt = Instant.now().toString()
        val payload =
            body +
                mapOf(
                    "reportId" to reportId,
                    "storedAt" to storedAt,
                    "platform" to platform,
                    "deviceId" to deviceId,
                    "deviceName" to deviceName,
                )

        val directory = File(context.filesDir, "feedback").apply { mkdirs() }
        File(directory, "${storedAt.replace(":", "-")}-$reportId.json")
            .writeText(JSONObject(payload).toString(2))
        return FeedbackRecord(reportId = reportId, storedAt = storedAt, payload = payload)
    }
}
