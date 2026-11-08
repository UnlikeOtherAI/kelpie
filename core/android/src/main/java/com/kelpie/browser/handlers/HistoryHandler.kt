package com.kelpie.browser.handlers

import com.kelpie.browser.browser.HistoryStore
import com.kelpie.browser.network.Router
import com.kelpie.browser.network.successResponse

class HistoryHandler(
    private val ctx: HandlerContext,
) {
    fun register(router: Router) {
        router.register("history-list") { list(it) }
        router.register("history-clear") { clear() }
    }

    private suspend fun list(body: Map<String, Any?>): Map<String, Any?> {
        val limit = (body["limit"] as? Number)?.toInt() ?: 100
        val entries = HistoryStore.toJSON()
        return successResponse(mapOf("entries" to entries.take(limit), "total" to entries.size))
    }

    private suspend fun clear(): Map<String, Any?> {
        HistoryStore.clear()
        return successResponse(mapOf("cleared" to true))
    }
}
