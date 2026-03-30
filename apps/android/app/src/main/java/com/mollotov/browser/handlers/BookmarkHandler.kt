package com.mollotov.browser.handlers

import com.mollotov.browser.browser.BookmarkStore
import com.mollotov.browser.network.Router
import com.mollotov.browser.network.errorResponse
import com.mollotov.browser.network.successResponse

class BookmarkHandler(private val ctx: HandlerContext) {
    fun register(router: Router) {
        router.register("bookmarks-list") { list() }
        router.register("bookmarks-add") { add(it) }
        router.register("bookmarks-remove") { remove(it) }
        router.register("bookmarks-clear") { clear() }
    }

    private suspend fun list(): Map<String, Any?> =
        successResponse(mapOf("bookmarks" to BookmarkStore.toJSON()))

    private suspend fun add(body: Map<String, Any?>): Map<String, Any?> {
        val url = body["url"] as? String ?: return errorResponse("MISSING_PARAM", "url is required")
        val title = body["title"] as? String ?: url
        BookmarkStore.add(title, url)
        return successResponse(mapOf("bookmarks" to BookmarkStore.toJSON()))
    }

    private suspend fun remove(body: Map<String, Any?>): Map<String, Any?> {
        val id = body["id"] as? String ?: return errorResponse("MISSING_PARAM", "id is required")
        BookmarkStore.remove(id)
        return successResponse(mapOf("bookmarks" to BookmarkStore.toJSON()))
    }

    private suspend fun clear(): Map<String, Any?> {
        BookmarkStore.clear()
        return successResponse(mapOf("cleared" to true))
    }
}
