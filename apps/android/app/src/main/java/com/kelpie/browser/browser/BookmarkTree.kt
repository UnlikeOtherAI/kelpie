package com.kelpie.browser.browser

import java.net.URI
import java.time.Instant
import java.util.UUID

data class Bookmark(
    val id: String = UUID.randomUUID().toString(),
    val title: String,
    val url: String = "",
    val createdAt: String = Instant.now().toString(),
    val kind: String = "bookmark",
    val parentId: String? = null,
) {
    val isFolder: Boolean get() = kind == "folder"
}

sealed class BookmarkMutation {
    data class Add(
        val bookmark: Bookmark,
    ) : BookmarkMutation()

    data class Update(
        val id: String,
        val title: String? = null,
        val url: String? = null,
    ) : BookmarkMutation()

    data class Move(
        val id: String,
        val parentId: String?,
        val beforeId: String? = null,
    ) : BookmarkMutation()

    data class Remove(
        val id: String,
    ) : BookmarkMutation()

    data class RemoveTree(
        val expected: List<Bookmark>,
    ) : BookmarkMutation()

    data class Restore(
        val removed: List<Bookmark>,
        val beforeId: String?,
    ) : BookmarkMutation()

    data object Clear : BookmarkMutation()
}

object BookmarkTree {
    fun validate(node: Bookmark) {
        require(node.title.isNotBlank()) { "Enter a name." }
        require(node.kind in setOf("bookmark", "folder")) { "Unknown favourite type." }
        if (node.isFolder) {
            require(node.url.isEmpty()) { "Folders cannot have a URL." }
        } else {
            val uri = runCatching { URI(node.url) }.getOrNull()
            require(uri != null && uri.scheme?.lowercase() in setOf("http", "https") && !uri.host.isNullOrEmpty()) {
                "Enter an HTTP or HTTPS URL with a host."
            }
        }
    }

    private fun parent(
        id: String?,
        nodes: List<Bookmark>,
    ) {
        require(id == null || nodes.any { it.id == id && it.isFolder }) { "The destination folder no longer exists." }
    }

    fun subtree(
        id: String,
        nodes: List<Bookmark>,
    ): List<Bookmark> {
        val root = nodes.firstOrNull { it.id == id } ?: return emptyList()
        val result = mutableListOf(root)
        val seen = mutableSetOf(id)
        var index = 0
        while (index < result.size) {
            val current = result[index++].id
            result += nodes.filter { it.parentId == current && seen.add(it.id) }
        }
        return result
    }

    fun apply(
        original: List<Bookmark>,
        mutation: BookmarkMutation,
    ): List<Bookmark> {
        val nodes = original.toMutableList()
        when (mutation) {
            is BookmarkMutation.Add -> {
                val node = mutation.bookmark
                validate(node)
                parent(node.parentId, nodes)
                if (nodes.any { it.id == node.id || (!node.isFolder && !it.isFolder && it.url == node.url && it.parentId == node.parentId) }) return nodes
                nodes += node
            }
            is BookmarkMutation.Update -> {
                val index = nodes.indexOfFirst { it.id == mutation.id }
                require(index >= 0) { "This favourite no longer exists." }
                val changed = nodes[index].copy(title = mutation.title ?: nodes[index].title, url = mutation.url ?: nodes[index].url)
                validate(changed)
                nodes[index] = changed
            }
            is BookmarkMutation.Move -> return move(nodes, mutation)
            is BookmarkMutation.Remove -> {
                require(nodes.none { it.id == mutation.id && it.isFolder }) { "Use subtree removal for folders." }
                nodes.removeAll { it.id == mutation.id }
            }
            is BookmarkMutation.RemoveTree -> {
                val root = mutation.expected.firstOrNull() ?: return nodes
                require(subtree(root.id, nodes) == mutation.expected) { "This folder changed on another device. Review it before removing it." }
                val ids = mutation.expected.map { it.id }.toSet()
                nodes.removeAll { it.id in ids }
            }
            is BookmarkMutation.Restore -> {
                val root = mutation.removed.firstOrNull() ?: return nodes
                require(nodes.none { existing -> mutation.removed.any { it.id == existing.id } }) { "These favourites have already been restored." }
                parent(root.parentId, nodes)
                val index = nodes.indexOfFirst { it.id == mutation.beforeId && it.parentId == root.parentId }.takeIf { it >= 0 } ?: nodes.size
                nodes.addAll(index, mutation.removed)
            }
            BookmarkMutation.Clear -> nodes.clear()
        }
        return nodes
    }

    private fun move(
        nodes: MutableList<Bookmark>,
        mutation: BookmarkMutation.Move,
    ): List<Bookmark> {
        val index = nodes.indexOfFirst { it.id == mutation.id }
        require(index >= 0) { "This favourite no longer exists." }
        parent(mutation.parentId, nodes)
        require(subtree(mutation.id, nodes).none { it.id == mutation.parentId }) { "A folder cannot be moved inside itself." }
        if (mutation.beforeId == mutation.id) return nodes
        val node = nodes.removeAt(index).copy(parentId = mutation.parentId)
        if (mutation.beforeId == null) {
            nodes += node
        } else {
            val destination = nodes.indexOfFirst { it.id == mutation.beforeId && it.parentId == mutation.parentId }
            require(destination >= 0) { "The destination has changed. Choose it again." }
            nodes.add(destination, node)
        }
        return nodes
    }

    fun normalized(original: List<Bookmark>): List<Bookmark> {
        require(original.map { it.id }.toSet().size == original.size) { "Duplicate favourite IDs in saved data." }
        val nodes = original.toMutableList()
        val folders = nodes.filter { it.isFolder }.map { it.id }.toSet()
        nodes.indices.forEach { index ->
            if (nodes[index].parentId != null && nodes[index].parentId !in folders) nodes[index] = nodes[index].copy(parentId = null)
            val seen = mutableSetOf(nodes[index].id)
            var ancestor = nodes[index].parentId
            while (ancestor != null) {
                if (!seen.add(ancestor)) {
                    nodes[index] = nodes[index].copy(parentId = null)
                    break
                }
                ancestor = nodes.firstOrNull { it.id == ancestor }?.parentId
            }
        }
        return nodes
    }
}
