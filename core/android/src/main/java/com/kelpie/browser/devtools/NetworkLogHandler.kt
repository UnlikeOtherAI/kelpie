package com.kelpie.browser.devtools

import com.kelpie.browser.handlers.HandlerContext
import com.kelpie.browser.handlers.diagnosticTab
import com.kelpie.browser.handlers.missingDiagnosticTab
import com.kelpie.browser.network.Router
import com.kelpie.browser.network.errorResponse
import com.kelpie.browser.network.successResponse
import kotlinx.coroutines.CancellationException
import java.time.Instant

class NetworkLogHandler(
    private val ctx: HandlerContext,
) {
    fun register(router: Router) {
        router.register("get-network-log") { getNetworkLog(it) }
        router.register("get-resource-timeline") { getResourceTimeline(it) }
    }

    private suspend fun getNetworkLog(body: Map<String, Any?>): Map<String, Any?> {
        val tab = ctx.diagnosticTab(body) ?: return missingDiagnosticTab()
        val type = body["type"] as? String
        val category = parseStatusCategory(body["status"])
        val since = parseSinceMillis(body["since"])
        val limit = (body["limit"] as? Int ?: 200).coerceAtLeast(0)
        return try {
            val page = ctx.withBrowserTarget(tab.webView) { ctx.evaluateJSReturningJSON(NETWORK_SNAPSHOT) }
            val entries = mergeNetworkEntries(page, tab.diagnostics.snapshotNetwork(), tab.diagnostics.documentResponse)
            val eligible =
                entries.filter {
                    (type == null || it["type"] == type) &&
                        (since == null || entryStartedMillis(it)?.let { millis -> millis >= since } == true)
                }
            val filtered =
                eligible.filter {
                    category == null || matchesStatusCategory(entryStatus(it), category, it["failure"] is String)
                }
            val limited = filtered.take(limit)
            successResponse(
                mapOf(
                    "entries" to limited,
                    "count" to limited.size,
                    "hasMore" to (filtered.size > limit),
                    "summary" to buildSummary(eligible),
                ),
            )
        } catch (cancelled: CancellationException) {
            throw cancelled
        } catch (e: Exception) {
            errorResponse("EVAL_ERROR", e.message ?: "Unknown error")
        }
    }

    /**
     * Pure status/`since` parsing helpers. Kept in a companion object so they are
     * testable on the plain JVM (`testDebugUnitTest`) without constructing a
     * `HandlerContext`, which requires the Android runtime.
     */
    companion object {
        /** Parse a `status` filter param into a category: "success", "error", or "pending"; null when absent/invalid. */
        internal fun parseStatusCategory(value: Any?): String? =
            when (val category = (value as? String)?.trim()?.lowercase()) {
                "success", "error", "pending" -> category
                else -> null
            }

        /**
         * Map an entry's HTTP status code to a category and test membership.
         * "success" = final status 200–399; "error" = status >= 400 or failed; "pending" = no final status (0/missing).
         */
        internal fun matchesStatusCategory(
            status: Int?,
            category: String,
            failed: Boolean = false,
        ): Boolean =
            when {
                failed -> category == "error"
                category == "success" -> status != null && status in 200..399
                category == "error" -> status != null && status >= 400
                category == "pending" -> status == null || status == 0
                else -> false
            }

        /** Parse a `since` param (epoch millis number or ISO-8601 string) into epoch millis, or null when absent. */
        internal fun parseSinceMillis(value: Any?): Long? =
            when (value) {
                is Long -> value
                is Int -> value.toLong()
                is Double -> value.toLong()
                is String -> value.trim().toLongOrNull() ?: parseIso8601Millis(value.trim())
                else -> null
            }

        internal fun parseIso8601Millis(iso: String): Long? =
            try {
                Instant.parse(iso).toEpochMilli()
            } catch (_: Exception) {
                null
            }
    }

    private fun entryStatus(entry: Map<String, Any?>): Int? =
        when (val s = entry["status"]) {
            is Int -> s
            is Long -> s.toInt()
            is Double -> s.toInt()
            else -> null
        }

    private fun entryStartedMillis(entry: Map<String, Any?>): Long? {
        val timing = entry["timing"] as? Map<*, *> ?: return null
        val started = timing["started"] as? String ?: return null
        return parseIso8601Millis(started)
    }

    /** Aggregate totals/byType/errors/loadTime over the filtered entries, mirroring iOS/macOS. */
    private fun buildSummary(entries: List<Map<String, Any?>>): Map<String, Any?> {
        var totalSize = 0L
        var totalTransfer = 0L
        val byType = mutableMapOf<String, Int>()
        var errors = 0
        var maxEnd = 0L

        for (entry in entries) {
            totalSize += numberAsLong(entry["size"])
            totalTransfer += numberAsLong(entry["transferSize"])
            val type = entry["type"] as? String ?: "other"
            byType[type] = (byType[type] ?: 0) + 1
            if (matchesStatusCategory(entryStatus(entry), "error", entry["failure"] is String)) errors++
            val timing = entry["timing"] as? Map<*, *>
            val total = numberAsLong(timing?.get("total"))
            if (total > maxEnd) maxEnd = total
        }

        return mapOf(
            "totalRequests" to entries.size,
            "totalSize" to totalSize,
            "totalTransferSize" to totalTransfer,
            "byType" to byType,
            "errors" to errors,
            "loadTime" to maxEnd,
        )
    }

    private fun numberAsLong(value: Any?): Long =
        when (value) {
            is Int -> value.toLong()
            is Long -> value
            is Double -> value.toLong()
            else -> 0L
        }

    private suspend fun getResourceTimeline(body: Map<String, Any?>): Map<String, Any?> {
        val tab = ctx.diagnosticTab(body) ?: return missingDiagnosticTab()
        return try {
            val page = ctx.withBrowserTarget(tab.webView) { ctx.evaluateJSReturningJSON(NETWORK_SNAPSHOT) }
            successResponse(page - setOf("entries", "timeOrigin"))
        } catch (cancelled: CancellationException) {
            throw cancelled
        } catch (e: Exception) {
            errorResponse("EVAL_ERROR", e.message ?: "Unknown error")
        }
    }
}
