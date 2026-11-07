package com.kelpie.browser.handlers

import com.kelpie.browser.browser.Bookmark
import com.kelpie.browser.browser.BookmarkMutation
import com.kelpie.browser.browser.BookmarkStore
import com.kelpie.browser.browser.BookmarkTree
import com.kelpie.browser.network.Router
import com.kelpie.browser.network.errorResponse
import com.kelpie.browser.network.successResponse
import java.util.UUID

class BookmarkHandler(
    private val ctx: HandlerContext,
) {
    fun register(router: Router) {
        listOf("list", "add", "create-folder", "update", "move", "remove", "clear").forEach { method ->
            router.register("bookmarks-$method") { handle(method, it) }
        }
    }

    private suspend fun handle(
        method: String,
        body: Map<String, Any?>,
    ): Map<String, Any?> =
        try {
            val mutation =
                when (method) {
                    "list" -> null
                    "add", "create-folder" -> {
                        val folder = method == "create-folder"
                        val url = if (folder) "" else body["url"] as? String ?: error("url is required")
                        val title = body["title"] as? String ?: url
                        BookmarkMutation.Add(Bookmark(title = title, url = url, kind = if (folder) "folder" else "bookmark", parentId = uuid("parentId", body)))
                    }
                    "update" -> {
                        require(body["title"] is String || body["url"] is String) { "title or url is required" }
                        BookmarkMutation.Update(id(body), text("title", body), text("url", body))
                    }
                    "move" -> {
                        require(body.containsKey("parentId")) { "parentId is required; use null for the top level" }
                        BookmarkMutation.Move(id(body), uuid("parentId", body), uuid("beforeId", body))
                    }
                    "remove" -> {
                        val id = id(body)
                        require(BookmarkStore.nodes.value.any { it.id == id }) { "This favourite no longer exists" }
                        BookmarkMutation.RemoveTree(BookmarkTree.subtree(id, BookmarkStore.nodes.value))
                    }
                    "clear" -> BookmarkMutation.Clear
                    else -> error("Unknown bookmarks operation")
                }
            mutation?.let { BookmarkStore.mutate(it)?.await() }
            successResponse(if (method == "clear") mapOf("cleared" to true, "bookmarks" to BookmarkStore.toJSON()) else mapOf("bookmarks" to BookmarkStore.toJSON()))
        } catch (error: IllegalArgumentException) {
            errorResponse("INVALID_PARAM", error.message ?: "Invalid favourites operation")
        } catch (error: Exception) {
            errorResponse("BOOKMARK_SYNC_FAILED", error.message ?: "Favourites could not be synced")
        }

    private fun id(body: Map<String, Any?>): String = uuid("id", body) ?: throw IllegalArgumentException("id is required")

    private fun uuid(
        field: String,
        body: Map<String, Any?>,
    ): String? {
        val value = body[field] ?: return null
        require(value is String && Regex("[a-fA-F0-9]{8}(-[a-fA-F0-9]{4}){3}-[a-fA-F0-9]{12}").matches(value)) { "$field must be a UUID" }
        return UUID.fromString(value).toString()
    }

    private fun text(
        field: String,
        body: Map<String, Any?>,
    ): String? {
        if (!body.containsKey(field)) return null
        return body[field] as? String ?: throw IllegalArgumentException("$field must be text")
    }
}
