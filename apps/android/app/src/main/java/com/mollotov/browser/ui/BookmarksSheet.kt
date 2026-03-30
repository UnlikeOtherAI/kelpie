package com.mollotov.browser.ui

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.mollotov.browser.browser.BookmarkStore

@Composable
fun BookmarksSheet(onNavigate: (String) -> Unit, onDismiss: () -> Unit) {
    val bookmarks by BookmarkStore.bookmarks.collectAsState()

    Column(modifier = Modifier.padding(16.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text("Bookmarks", style = MaterialTheme.typography.titleMedium, modifier = Modifier.weight(1f))
            if (bookmarks.isNotEmpty()) {
                TextButton(onClick = { BookmarkStore.clear() }) { Text("Clear All") }
            }
        }
        Spacer(Modifier.height(8.dp))
        if (bookmarks.isEmpty()) {
            Text("No bookmarks. Add via CLI or MCP.", style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
        } else {
            LazyColumn {
                items(bookmarks, key = { it.id }) { bookmark ->
                    Column(
                        modifier = Modifier
                            .fillMaxWidth()
                            .clickable { onNavigate(bookmark.url); onDismiss() }
                            .padding(vertical = 8.dp),
                    ) {
                        Text(bookmark.title, style = MaterialTheme.typography.bodyMedium)
                        Text(bookmark.url, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 1, overflow = TextOverflow.Ellipsis)
                    }
                }
            }
        }
        Spacer(Modifier.height(16.dp))
    }
}
