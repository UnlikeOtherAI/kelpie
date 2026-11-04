package com.kelpie.browser.browser

import android.content.Context
import android.content.SharedPreferences
import com.kelpie.browser.account.AccountBookmarks
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Deferred
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.serialization.json.Json
import java.util.UUID

object BookmarkStore {
    private const val PREFS_NAME = "kelpie_bookmarks"
    private const val DATA_KEY = "tree_v1"
    private var account: AccountBookmarks? = null
    private lateinit var prefs: SharedPreferences
    private val lock = Any()
    private var loadError: Exception? = null
    private val _nodes = MutableStateFlow<List<Bookmark>>(emptyList())
    private val _bookmarks = MutableStateFlow<List<Bookmark>>(emptyList())
    val nodes: StateFlow<List<Bookmark>> = _nodes.asStateFlow()
    val bookmarks: StateFlow<List<Bookmark>> = _bookmarks.asStateFlow()
    val syncError = MutableStateFlow<String?>(null)
    val isSyncing = MutableStateFlow(false)
    val canUndoRemoval = MutableStateFlow(false)
    val sessionGeneration = MutableStateFlow(UUID.randomUUID().toString())
    val generation: String get() = sessionGeneration.value
    private var undoRemoval: Pair<BookmarkMutation, String>? = null

    private fun publish(value: List<Bookmark>) {
        _nodes.value = value
        _bookmarks.value = value.filterNot { it.isFolder }
    }

    fun useAccount() = synchronized(lock) {
        resetSession()
        publish(emptyList())
        account = AccountBookmarks({ value -> synchronized(lock) { publish(value) } }, { busy, error ->
            isSyncing.value = busy
            syncError.value = error
        })
        account?.enableEvents()
        account?.enqueue()
    }

    fun useLocalBookmarks() = synchronized(lock) {
        resetSession()
        account = null
        if (::prefs.isInitialized) load()
    }

    private fun resetSession() {
        account?.invalidate()
        sessionGeneration.value = UUID.randomUUID().toString()
        loadError = null
        syncError.value = null
        isSyncing.value = false
        undoRemoval = null
        canUndoRemoval.value = false
    }

    fun init(context: Context) = synchronized(lock) {
        prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        if (account == null) load()
    }

    fun refreshAccountBookmarks() = synchronized(lock) { account?.enqueue() }
    suspend fun flush() {
        val current = synchronized(lock) { account }
        current?.flush()
        synchronized(lock) {
            if (current !== account) throw kotlinx.coroutines.CancellationException()
            syncError.value?.let { throw IllegalStateException(it) }
        }
    }

    fun mutate(mutation: BookmarkMutation): Deferred<Unit>? = synchronized(lock) {
        account?.let { return@synchronized it.enqueue(mutation) }
        try {
            loadError?.let { throw it }
            val changed = BookmarkTree.apply(_nodes.value, mutation)
            val encoded = AccountBookmarks.encode(changed).toString()
            check(prefs.edit().putString(DATA_KEY, encoded).commit()) { "Favourites could not be saved." }
            publish(changed)
            syncError.value = null
            null
        } catch (error: Exception) {
            syncError.value = error.message
            CompletableDeferred<Unit>().also { it.completeExceptionally(error) }
        }
    }

    fun add(title: String, url: String, parentId: String? = null): Deferred<Unit>? =
        mutate(BookmarkMutation.Add(Bookmark(title = title.ifEmpty { url }, url = url, parentId = parentId)))
    fun remove(id: String): Deferred<Unit>? = mutate(BookmarkMutation.RemoveTree(BookmarkTree.subtree(id, _nodes.value)))
    fun clear(): Deferred<Unit>? = mutate(BookmarkMutation.Clear)
    fun children(parentId: String?): List<Bookmark> = _nodes.value.filter { it.parentId == parentId }

    suspend fun removeWithUndo(id: String) {
        val session = generation
        val removed = BookmarkTree.subtree(id, _nodes.value)
        val root = removed.firstOrNull() ?: return
        val siblings = children(root.parentId)
        val next = siblings.getOrNull(siblings.indexOfFirst { it.id == id } + 1)?.id
        mutate(BookmarkMutation.RemoveTree(removed))?.await()
        if (generation != session) throw kotlinx.coroutines.CancellationException()
        undoRemoval = BookmarkMutation.Restore(removed, next) to session
        canUndoRemoval.value = true
    }

    suspend fun undoLastRemoval() {
        val (mutation, session) = undoRemoval ?: return
        if (generation != session) return
        mutate(mutation)?.await()
        if (generation != session) throw kotlinx.coroutines.CancellationException()
        undoRemoval = null
        canUndoRemoval.value = false
    }

    fun toJSON(): List<Map<String, Any?>> = _nodes.value.map {
        mapOf("id" to it.id, "title" to it.title, "url" to it.url, "createdAt" to it.createdAt, "kind" to it.kind, "parentId" to it.parentId)
    }

    private fun load() {
        try {
            val raw = prefs.getString(DATA_KEY, null) ?: prefs.getString("data", "[]") ?: "[]"
            val parsed = Json.parseToJsonElement(raw) as? kotlinx.serialization.json.JsonArray
                ?: error("Saved favourites could not be read.")
            val decoded = AccountBookmarks.decode(parsed)
            check(decoded.size == parsed.size) { "Saved favourites have an unsupported format." }
            publish(decoded)
            loadError = null
        } catch (error: Exception) {
            loadError = error
            syncError.value = "Saved favourites could not be read. The original data has been preserved."
        }
    }
}
