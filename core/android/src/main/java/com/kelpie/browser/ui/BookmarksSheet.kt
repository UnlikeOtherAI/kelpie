package com.kelpie.browser.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectDragGesturesAfterLongPress
import androidx.compose.foundation.gestures.scrollBy
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Bookmark
import androidx.compose.material.icons.filled.ChevronRight
import androidx.compose.material.icons.filled.DragHandle
import androidx.compose.material.icons.filled.ExpandMore
import androidx.compose.material.icons.filled.Folder
import androidx.compose.material.icons.filled.MoreHoriz
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.boundsInRoot
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import com.kelpie.browser.browser.Bookmark
import com.kelpie.browser.browser.BookmarkMutation
import com.kelpie.browser.browser.BookmarkStore
import com.kelpie.browser.browser.BookmarkTree
import kotlinx.coroutines.launch

@Composable
fun BookmarksSheet(
    currentTitle: String,
    currentUrl: String,
    onNavigate: (String) -> Unit,
    onDismiss: () -> Unit,
) {
    Dialog(onDismissRequest = onDismiss, properties = DialogProperties(usePlatformDefaultWidth = false, decorFitsSystemWindows = false)) {
        BoxWithConstraints(Modifier.fillMaxSize().clickable(onClick = onDismiss)) {
            val drawer = maxWidth >= 600.dp
            Surface(
                Modifier
                    .fillMaxHeight()
                    .width(if (drawer) minOf(420.dp, maxWidth * 0.55f) else maxWidth)
                    .clickable {},
                color = MaterialTheme.colorScheme.surface,
            ) {
                FavouritesTreeContent(currentTitle, currentUrl, onNavigate, onDismiss, !drawer)
            }
        }
    }
}

@Composable
private fun FavouritesTreeContent(
    currentTitle: String,
    currentUrl: String,
    onNavigate: (String) -> Unit,
    onDismiss: () -> Unit,
    closeOnNavigate: Boolean,
) {
    val nodes by BookmarkStore.nodes.collectAsState()
    val generation by BookmarkStore.sessionGeneration.collectAsState()
    val syncError by BookmarkStore.syncError.collectAsState()
    val syncing by BookmarkStore.isSyncing.collectAsState()
    val canUndo by BookmarkStore.canUndoRemoval.collectAsState()
    val scope = rememberCoroutineScope()
    val list = rememberLazyListState()
    var expanded by remember { mutableStateOf(setOf<String>()) }
    var editing by remember { mutableStateOf<Bookmark?>(null) }
    var moving by remember { mutableStateOf<Bookmark?>(null) }
    var removing by remember { mutableStateOf<Bookmark?>(null) }
    var dragged by remember { mutableStateOf<String?>(null) }
    var point by remember { mutableStateOf(Offset.Zero) }
    var sourceGeneration by remember { mutableStateOf("") }
    var listBounds by remember { mutableStateOf(Rect.Zero) }
    val bounds = remember { mutableStateMapOf<String, Rect>() }
    val rows = remember(nodes, expanded) { visibleFavourites(nodes, expanded) }
    val canAddPage = runCatching { BookmarkTree.validate(Bookmark(title = currentTitle.ifEmpty { currentUrl }, url = currentUrl)) }.isSuccess

    fun finishDrag() {
        val id = dragged
        dragged = null
        if (id == null || sourceGeneration != BookmarkStore.generation) return
        val target = bounds.entries.firstOrNull { it.value.contains(point) } ?: return
        val node = nodes.firstOrNull { it.id == target.key }
        val mutation =
            if (node == null) {
                BookmarkMutation.Move(id, null)
            } else {
                val fraction = (point.y - target.value.top) / target.value.height
                if (node.isFolder && fraction in 0.25f..0.75f) {
                    BookmarkMutation.Move(id, node.id)
                } else {
                    val siblings = nodes.filter { it.parentId == node.parentId }
                    val before = if (fraction < 0.5f) node.id else siblings.getOrNull(siblings.indexOf(node) + 1)?.id
                    BookmarkMutation.Move(id, node.parentId, before)
                }
            }
        BookmarkStore.mutate(mutation)
    }
    Column(Modifier.fillMaxSize().safeDrawingPadding().padding(horizontal = 12.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            TextButton(onClick = onDismiss, modifier = Modifier.testTag("browser.bookmarks.done")) { Text("Done") }
            Text("Favourites", style = MaterialTheme.typography.titleLarge, modifier = Modifier.weight(1f))
            var addMenu by remember { mutableStateOf(false) }
            Box {
                IconButton(onClick = { addMenu = true }) { Icon(Icons.Default.Add, "Add favourite or folder") }
                DropdownMenu(expanded = addMenu, onDismissRequest = { addMenu = false }) {
                    DropdownMenuItem(text = { Text("New Folder") }, onClick = {
                        addMenu = false
                        editing = Bookmark(title = "New Folder", kind = "folder")
                    })
                    DropdownMenuItem(
                        text = { Text("Add Current Page") },
                        onClick = {
                            addMenu = false
                            BookmarkStore.add(currentTitle, currentUrl)
                        },
                        enabled = canAddPage,
                    )
                }
            }
        }
        Text(
            "Top Level",
            modifier =
                Modifier
                    .fillMaxWidth()
                    .background(MaterialTheme.colorScheme.surfaceVariant)
                    .padding(10.dp)
                    .onGloballyPositioned { bounds["root"] = it.boundsInRoot() }
                    .testTag("browser.bookmarks.root"),
        )
        LazyColumn(state = list, modifier = Modifier.weight(1f).onGloballyPositioned { listBounds = it.boundsInRoot() }) {
            if (nodes.isEmpty()) item { Text("No favourites yet. Add a page or create a folder.", modifier = Modifier.padding(16.dp)) }
            items(rows, key = { it.first.id }) { (node, depth) ->
                DisposableEffect(node.id) { onDispose { bounds.remove(node.id) } }
                var menu by remember { mutableStateOf(false) }
                var handleOrigin by remember { mutableStateOf(Offset.Zero) }
                val target = dragged != null && bounds[node.id]?.contains(point) == true
                Row(
                    Modifier
                        .fillMaxWidth()
                        .heightIn(min = 56.dp)
                        .background(if (target) MaterialTheme.colorScheme.secondaryContainer else MaterialTheme.colorScheme.surface)
                        .onGloballyPositioned { bounds[node.id] = it.boundsInRoot() }
                        .padding(start = (minOf(depth, 8) * 16).dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Row(
                        Modifier
                            .weight(1f)
                            .clickable {
                                if (node.isFolder) {
                                    expanded = if (node.id in expanded) expanded - node.id else expanded + node.id
                                } else {
                                    onNavigate(node.url)
                                    if (closeOnNavigate) onDismiss()
                                }
                            }.padding(vertical = 10.dp)
                            .testTag("browser.bookmarks.row.${node.id}"),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Icon(
                            if (node.id in expanded) Icons.Default.ExpandMore else Icons.Default.ChevronRight,
                            null,
                            Modifier.size(20.dp).alpha(if (node.isFolder) 1f else 0f),
                        )
                        Icon(if (node.isFolder) Icons.Default.Folder else Icons.Default.Bookmark, null, Modifier.padding(end = 8.dp).size(20.dp))
                        Column {
                            Text(node.title, maxLines = 1)
                            if (!node.isFolder) Text(node.url, maxLines = 1, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                        }
                    }
                    Box {
                        IconButton(onClick = { menu = true }) { Icon(Icons.Default.MoreHoriz, "Actions for ${node.title}") }
                        DropdownMenu(expanded = menu, onDismissRequest = { menu = false }) {
                            DropdownMenuItem(text = { Text("Edit") }, onClick = {
                                menu = false
                                editing = node
                            })
                            DropdownMenuItem(text = { Text("Move…") }, onClick = {
                                menu = false
                                moving = node
                            })
                            if (node.isFolder) {
                                DropdownMenuItem(text = { Text("New Folder Inside") }, onClick = {
                                    menu = false
                                    editing = Bookmark(title = "New Folder", kind = "folder", parentId = node.id)
                                })
                                DropdownMenuItem(text = { Text("Add Current Page Here") }, enabled = canAddPage, onClick = {
                                    menu = false
                                    BookmarkStore.add(currentTitle, currentUrl, node.id)
                                })
                            }
                            DropdownMenuItem(text = { Text("Remove") }, onClick = {
                                menu = false
                                removing = node
                            })
                        }
                    }
                    Icon(
                        Icons.Default.DragHandle,
                        "Drag ${node.title}",
                        Modifier
                            .size(40.dp)
                            .padding(8.dp)
                            .onGloballyPositioned { handleOrigin = it.boundsInRoot().topLeft }
                            .pointerInput(node.id, generation) {
                                detectDragGesturesAfterLongPress(onDragStart = { start ->
                                    dragged = node.id
                                    sourceGeneration = BookmarkStore.generation
                                    point = handleOrigin + start
                                }, onDragCancel = { dragged = null }, onDragEnd = { finishDrag() }) { change, delta ->
                                    change.consume()
                                    point += delta
                                    val scroll =
                                        when {
                                            point.y < listBounds.top + 48 -> -16f
                                            point.y > listBounds.bottom - 48 -> 16f
                                            else -> 0f
                                        }
                                    if (scroll != 0f) scope.launch { list.scrollBy(scroll) }
                                }
                            },
                    )
                }
            }
        }
        syncError?.let { Text(it, color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodySmall) }
        if (syncing) Text("Saving favourites…", style = MaterialTheme.typography.bodySmall)
        if (canUndo) TextButton(onClick = { scope.launch { runCatching { BookmarkStore.undoLastRemoval() } } }, modifier = Modifier.testTag("browser.bookmarks.undo")) { Text("Undo Remove") }
    }
    editing?.let { node -> FavouriteEditDialog(node) { editing = null } }
    moving?.let { node -> FavouriteMoveDialog(node, nodes) { moving = null } }
    removing?.let { node ->
        AlertDialog(
            onDismissRequest = { removing = null },
            title = { Text("Remove this favourite?") },
            text = { Text(if (node.isFolder) "This removes the folder and everything inside it. You can undo it." else "You can undo this removal.") },
            confirmButton = {
                TextButton(onClick = {
                    removing = null
                    scope.launch { runCatching { BookmarkStore.removeWithUndo(node.id) } }
                }) { Text("Remove") }
            },
            dismissButton = { TextButton(onClick = { removing = null }) { Text("Cancel") } },
        )
    }
    LaunchedEffect(generation) {
        editing = null
        moving = null
        removing = null
        dragged = null
        expanded = emptySet()
    }
    LaunchedEffect(nodes, expanded) { bounds.keys.filter { it != "root" && rows.none { row -> row.first.id == it } }.forEach(bounds::remove) }
}

private fun visibleFavourites(
    nodes: List<Bookmark>,
    expanded: Set<String>,
): List<Pair<Bookmark, Int>> {
    val result = mutableListOf<Pair<Bookmark, Int>>()
    val pending =
        nodes
            .filter { it.parentId == null }
            .reversed()
            .map { it to 0 }
            .toMutableList()
    while (pending.isNotEmpty()) {
        val (node, depth) = pending.removeAt(pending.lastIndex)
        result += node to depth
        if (node.id in expanded) pending += nodes.filter { it.parentId == node.id }.reversed().map { it to depth + 1 }
    }
    return result
}
