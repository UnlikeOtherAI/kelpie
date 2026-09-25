package com.kelpie.browser.handlers

import com.kelpie.browser.browser.BookmarkStore
import com.kelpie.browser.network.Router
import com.kelpie.browser.network.errorResponse
import com.kelpie.browser.network.successResponse

class BookmarkHandler(
    private val ctx: HandlerContext,
) {
    fun register(router: Router) {
        router.register("bookmarks-list") { list() }
        router.register("bookmarks-add") { add(it) }
        router.register("bookmarks-remove") { remove(it) }
        router.register("bookmarks-clear") { clear() }
    }

    private suspend fun list(): Map<String, Any?> = savedResponse()

    private suspend fun add(body: Map<String, Any?>): Map<String, Any?> {
        val url = body["url"] as? String ?: return errorResponse("MISSING_PARAM", "url is required")
        val title = body["title"] as? String ?: url
        return savedResponse(BookmarkStore.add(title, url))
    }

    private suspend fun remove(body: Map<String, Any?>): Map<String, Any?> {
        val id = body["id"] as? String ?: return errorResponse("MISSING_PARAM", "id is required")
        return savedResponse(BookmarkStore.remove(id))
    }

    private suspend fun clear(): Map<String, Any?> {
        return savedResponse(BookmarkStore.clear(), cleared = true)
    }
    private suspend fun savedResponse(operation: kotlinx.coroutines.Deferred<Unit>? = null, cleared: Boolean = false): Map<String, Any?> =
        try {
            operation?.await()
            if (cleared) successResponse(mapOf("cleared" to true)) else successResponse(mapOf("bookmarks" to BookmarkStore.toJSON()))
        } catch (error: Exception) {
            errorResponse("BOOKMARK_SYNC_FAILED", error.message ?: "Favourites could not be synced.")
        }
}
