package com.kelpie.browser

import com.kelpie.browser.account.UOASettingsValue
import com.kelpie.browser.browser.Bookmark
import com.kelpie.browser.browser.BookmarkMutation
import com.kelpie.browser.browser.BookmarkTree
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test

class FavouritesTreeTests {
    @Test
    fun nestedMovesKeepChildrenAndRejectCyclesAndStaleAnchors() {
        val folder = Bookmark(title = "Work", kind = "folder")
        val child = Bookmark(title = "Docs", kind = "folder", parentId = folder.id)
        val page = Bookmark(title = "Page", url = "https://example.com", parentId = child.id)
        val other = Bookmark(title = "Other", kind = "folder")
        val nodes = listOf(folder, child, page, other)
        val moved = BookmarkTree.apply(nodes, BookmarkMutation.Move(child.id, other.id))
        assertEquals(child.id, moved.first { it.id == page.id }.parentId)
        assertEquals(other.id, moved.first { it.id == child.id }.parentId)
        assertThrows(IllegalArgumentException::class.java) { BookmarkTree.apply(nodes, BookmarkMutation.Move(folder.id, child.id)) }
        assertThrows(IllegalArgumentException::class.java) { BookmarkTree.apply(nodes, BookmarkMutation.Move(other.id, folder.id, page.id)) }
        assertEquals(listOf(other.id, folder.id), BookmarkTree.apply(nodes, BookmarkMutation.Move(other.id, null, folder.id)).filter { it.parentId == null }.map { it.id })
    }

    @Test
    fun removalRejectsConcurrentContentsAndUndoPreservesOtherEdits() {
        val folder = Bookmark(title = "Work", kind = "folder")
        val page = Bookmark(title = "Page", url = "https://example.com", parentId = folder.id)
        val other = Bookmark(title = "Other", url = "https://other.example")
        val nodes = listOf(folder, page, other)
        val removed = BookmarkTree.subtree(folder.id, nodes)
        val mutation = BookmarkMutation.RemoveTree(removed)
        assertEquals(listOf(other), BookmarkTree.apply(nodes, mutation))
        assertThrows(IllegalArgumentException::class.java) { BookmarkTree.apply(nodes + Bookmark(title = "New", url = "https://new.example", parentId = folder.id), mutation) }
        val renamed = other.copy(title = "Renamed elsewhere")
        val restored = BookmarkTree.apply(listOf(renamed), BookmarkMutation.Restore(removed, other.id))
        assertEquals(listOf(folder, page, renamed), restored)
        assertThrows(IllegalArgumentException::class.java) { BookmarkTree.apply(restored, BookmarkMutation.Restore(removed, null)) }
    }

    @Test
    fun deltasAreAtomicAndRequireTheExactBaseVersion() {
        val state = UOASettingsValue()
        val first = "\"" + "a".repeat(64) + "\""
        val next = "\"" + "b".repeat(64) + "\""
        fun frame(type: String, version: String, operation: String? = null, base: String = first) = buildJsonObject {
            put("protocolVersion", 1)
            put("namespace", "browser")
            put("key", "bookmarks")
            put("type", type)
            put("version", version)
            if (operation == null) put("value", JsonArray(listOf("a", "b", "c").map(::JsonPrimitive))) else {
                put("baseVersion", base)
                put("operation", Json.parseToJsonElement(operation))
            }
        }.toString()
        assertTrue(state.receive(frame("settings.snapshot", first), "browser", "bookmarks"))
        val invalid = frame("settings.delta", next, """{"type":"splice","index":8,"deleteCount":1,"items":[]}""")
        assertThrows(IllegalArgumentException::class.java) { state.receive(invalid, "browser", "bookmarks") }
        assertEquals(first, state.version)
        val valid = frame("settings.delta", next, """{"type":"splice","index":1,"deleteCount":1,"items":["new"]}""")
        assertTrue(state.receive(valid, "browser", "bookmarks"))
        assertEquals(Json.parseToJsonElement("""["a","new","c"]"""), state.value)
        assertFalse(state.receive(valid, "browser", "bookmarks"))
        assertThrows(IllegalArgumentException::class.java) { state.receive(frame("settings.delta", first, """{"type":"replace","value":null}"""), "browser", "bookmarks") }
    }
}
