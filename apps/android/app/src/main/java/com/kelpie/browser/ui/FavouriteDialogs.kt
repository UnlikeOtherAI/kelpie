package com.kelpie.browser.ui

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Box
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import com.kelpie.browser.browser.Bookmark
import com.kelpie.browser.browser.BookmarkMutation
import com.kelpie.browser.browser.BookmarkStore
import com.kelpie.browser.browser.BookmarkTree
import kotlinx.coroutines.launch

@Composable
fun FavouriteEditDialog(node: Bookmark, dismiss: () -> Unit) {
    var title by remember(node.id) { mutableStateOf(node.title) }
    var url by remember(node.id) { mutableStateOf(node.url) }
    val error by BookmarkStore.syncError.collectAsState()
    val scope = rememberCoroutineScope()
    AlertDialog(onDismissRequest = dismiss, title = { Text(if (node.isFolder) "Edit Folder" else "Edit Favourite") }, text = {
        Column {
            OutlinedTextField(value = title, onValueChange = { title = it }, label = { Text("Name") }, modifier = Modifier.testTag("browser.bookmarks.name"))
            if (!node.isFolder) OutlinedTextField(value = url, onValueChange = { url = it }, label = { Text("URL") }, modifier = Modifier.testTag("browser.bookmarks.url"))
            error?.let { Text(it, color = MaterialTheme.colorScheme.error) }
        }
    }, confirmButton = {
        TextButton(onClick = {
            scope.launch {
                val mutation = if (BookmarkStore.nodes.value.any { it.id == node.id }) BookmarkMutation.Update(node.id, title, if (node.isFolder) null else url)
                else BookmarkMutation.Add(node.copy(title = title, url = if (node.isFolder) "" else url))
                runCatching { BookmarkStore.mutate(mutation)?.await() }.onSuccess { dismiss() }
            }
        }, modifier = Modifier.testTag("browser.bookmarks.save")) { Text("Save") }
    }, dismissButton = { TextButton(onClick = dismiss) { Text("Cancel") } })
}

@Composable
fun FavouriteMoveDialog(node: Bookmark, nodes: List<Bookmark>, dismiss: () -> Unit) {
    var parent by remember(node.id) { mutableStateOf(node.parentId) }
    var before by remember(node.id) { mutableStateOf<String?>(null) }
    val excluded = BookmarkTree.subtree(node.id, nodes).map { it.id }.toSet()
    val scope = rememberCoroutineScope()
    val error by BookmarkStore.syncError.collectAsState()
    AlertDialog(onDismissRequest = dismiss, title = { Text("Move Favourite") }, text = {
        Column {
            FavouriteChoice("Folder", parent, listOf(null to "Top Level") + nodes.filter { it.isFolder && it.id !in excluded }.map { it.id to it.title }) { parent = it; before = null }
            FavouriteChoice("Position", before, listOf(null to "At the End") + nodes.filter { it.parentId == parent && it.id != node.id }.map { it.id to "Before ${it.title}" }) { before = it }
            error?.let { Text(it, color = MaterialTheme.colorScheme.error) }
        }
    }, confirmButton = { TextButton(onClick = { scope.launch { runCatching { BookmarkStore.mutate(BookmarkMutation.Move(node.id, parent, before))?.await() }.onSuccess { dismiss() } } }) { Text("Move") } },
        dismissButton = { TextButton(onClick = dismiss) { Text("Cancel") } })
}

@Composable
private fun FavouriteChoice(label: String, value: String?, choices: List<Pair<String?, String>>, select: (String?) -> Unit) {
    var expanded by remember { mutableStateOf(false) }
    Box {
        TextButton(onClick = { expanded = true }) { Text("$label: ${choices.firstOrNull { it.first == value }?.second ?: "Top Level"}") }
        DropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
            choices.forEach { (id, title) -> DropdownMenuItem(text = { Text(title) }, onClick = { expanded = false; select(id) }) }
        }
    }
}
