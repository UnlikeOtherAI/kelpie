package com.kelpie.browser.handlers

import com.kelpie.browser.browser.NetworkTrafficStore
import com.kelpie.browser.network.Router
import com.kelpie.browser.network.errorResponse
import com.kelpie.browser.network.successResponse

class NetworkInspectorHandler(
    private val ctx: HandlerContext,
) {
    fun register(router: Router) {
        router.register("network-list") { list(it) }
        router.register("network-detail") { detail(it) }
        router.register("network-select") { select(it) }
        router.register("network-current") { current() }
        router.register("network-clear") { clear() }
    }

    private suspend fun list(body: Map<String, Any?>): Map<String, Any?> {
        val entries =
            NetworkTrafficStore.toSummaryList(
                method = body["method"] as? String,
                category = body["category"] as? String,
                statusRange = body["statusRange"] as? String,
                urlPattern = body["urlPattern"] as? String,
            )
        return successResponse(mapOf("entries" to entries, "total" to NetworkTrafficStore.entries.value.size))
    }

    private suspend fun detail(body: Map<String, Any?>): Map<String, Any?> {
        val index =
            (body["index"] as? Number)?.toInt()
                ?: return errorResponse("INVALID_INDEX", "index is required and must be valid")
        val list = NetworkTrafficStore.entries.value
        if (index !in list.indices) return errorResponse("INVALID_INDEX", "index out of range")
        return successResponse(NetworkTrafficStore.entryToMap(list[index]))
    }

    private suspend fun select(body: Map<String, Any?>): Map<String, Any?> {
        val index = (body["index"] as? Number)?.toInt()
        val list = NetworkTrafficStore.entries.value
        if (index != null && index in list.indices) {
            NetworkTrafficStore.select(index)
            return successResponse(NetworkTrafficStore.entryToMap(list[index]))
        }
        val pattern = body["urlPattern"] as? String
        if (pattern != null) {
            val idx = list.indexOfLast { it.url.contains(pattern) }
            if (idx >= 0) {
                NetworkTrafficStore.select(idx)
                return successResponse(NetworkTrafficStore.entryToMap(list[idx]))
            }
            return errorResponse("NOT_FOUND", "No request matching '$pattern'")
        }
        return errorResponse("MISSING_PARAM", "index or urlPattern is required")
    }

    private suspend fun current(): Map<String, Any?> {
        val entry =
            NetworkTrafficStore.selectedEntry
                ?: return errorResponse("NONE_SELECTED", "No request currently selected")
        return successResponse(NetworkTrafficStore.entryToMap(entry))
    }

    private suspend fun clear(): Map<String, Any?> {
        NetworkTrafficStore.clear()
        return successResponse(mapOf("cleared" to true))
    }
}
