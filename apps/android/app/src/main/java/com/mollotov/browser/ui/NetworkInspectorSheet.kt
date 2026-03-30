package com.mollotov.browser.ui

import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.FilterChip
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.mollotov.browser.browser.NetworkTrafficStore
import com.mollotov.browser.browser.TrafficEntry

@Composable
fun NetworkInspectorSheet(onDismiss: () -> Unit) {
    val entries by NetworkTrafficStore.entries.collectAsState()
    var methodFilter by remember { mutableStateOf<String?>(null) }
    var categoryFilter by remember { mutableStateOf<String?>(null) }
    var selectedEntry by remember { mutableStateOf<Pair<Int, TrafficEntry>?>(null) }

    Column(modifier = Modifier.padding(16.dp)) {
        if (selectedEntry != null) {
            NetworkDetailContent(
                entry = selectedEntry!!.second,
                index = selectedEntry!!.first,
                onBack = { selectedEntry = null },
            )
        } else {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text("Network", style = MaterialTheme.typography.titleMedium, modifier = Modifier.weight(1f))
                TextButton(onClick = { NetworkTrafficStore.clear() }) { Text("Clear") }
            }
            // Filter chips
            Row(
                modifier = Modifier.horizontalScroll(rememberScrollState()),
                horizontalArrangement = Arrangement.spacedBy(6.dp),
            ) {
                FilterChip(selected = methodFilter == null && categoryFilter == null, onClick = { methodFilter = null; categoryFilter = null }, label = { Text("All") })
                listOf("GET", "POST", "PUT", "DELETE").forEach { m ->
                    FilterChip(selected = methodFilter == m, onClick = { methodFilter = if (methodFilter == m) null else m }, label = { Text(m) })
                }
                listOf("JSON", "HTML", "JS", "CSS", "Image").forEach { c ->
                    FilterChip(selected = categoryFilter == c, onClick = { categoryFilter = if (categoryFilter == c) null else c }, label = { Text(c) })
                }
            }
            Spacer(Modifier.height(8.dp))

            val filtered = entries.withIndex().filter { (_, e) ->
                (methodFilter == null || e.method == methodFilter) &&
                    (categoryFilter == null || e.category == categoryFilter)
            }.toList()

            if (filtered.isEmpty()) {
                Text("No requests captured.", style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
            } else {
                LazyColumn {
                    items(filtered.size) { i ->
                        val (idx, entry) = filtered[i]
                        Row(
                            modifier = Modifier
                                .fillMaxWidth()
                                .clickable {
                                    selectedEntry = idx to entry
                                    NetworkTrafficStore.select(idx)
                                }
                                .padding(vertical = 6.dp),
                            verticalAlignment = Alignment.CenterVertically,
                        ) {
                            Text(
                                entry.method,
                                fontSize = 11.sp,
                                fontWeight = FontWeight.Bold,
                                color = methodColor(entry.method),
                                modifier = Modifier.width(48.dp),
                            )
                            Text(
                                "${entry.statusCode}",
                                fontSize = 11.sp,
                                color = statusColor(entry.statusCode),
                                modifier = Modifier.width(30.dp),
                            )
                            Column(modifier = Modifier.weight(1f)) {
                                Text(shortenUrl(entry.url), fontSize = 11.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
                                Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                                    Text(entry.category, fontSize = 9.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
                                    Text("${entry.duration}ms", fontSize = 9.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
                                    Text(formatBytes(entry.size), fontSize = 9.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
                                }
                            }
                        }
                    }
                }
            }
        }
        Spacer(Modifier.height(16.dp))
    }
}

@Composable
private fun NetworkDetailContent(entry: TrafficEntry, index: Int, onBack: () -> Unit) {
    Column {
        TextButton(onClick = onBack) { Text("< Back") }
        Text("Request #$index", style = MaterialTheme.typography.titleSmall)
        Spacer(Modifier.height(8.dp))

        Text("REQUEST", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.primary)
        DetailRow("Method", entry.method)
        DetailRow("URL", entry.url)
        if (!entry.requestBody.isNullOrEmpty()) DetailRow("Body", entry.requestBody)
        if (entry.requestHeaders.isNotEmpty()) {
            Text("Headers", style = MaterialTheme.typography.labelSmall, modifier = Modifier.padding(top = 4.dp))
            entry.requestHeaders.forEach { (k, v) -> DetailRow(k, v) }
        }

        Spacer(Modifier.height(12.dp))
        Text("RESPONSE", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.primary)
        DetailRow("Status", "${entry.statusCode}")
        DetailRow("Content-Type", entry.contentType)
        DetailRow("Size", "${entry.size} bytes")
        DetailRow("Duration", "${entry.duration} ms")
        if (!entry.responseBody.isNullOrEmpty()) DetailRow("Body", entry.responseBody)
        if (entry.responseHeaders.isNotEmpty()) {
            Text("Headers", style = MaterialTheme.typography.labelSmall, modifier = Modifier.padding(top = 4.dp))
            entry.responseHeaders.forEach { (k, v) -> DetailRow(k, v) }
        }
    }
}

@Composable
private fun DetailRow(label: String, value: String) {
    Column(modifier = Modifier.padding(vertical = 2.dp)) {
        Text(label, fontSize = 10.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
        Text(value, fontSize = 12.sp)
    }
}

private fun methodColor(method: String): Color = when (method) {
    "GET" -> Color(0xFF2196F3)
    "POST" -> Color(0xFF4CAF50)
    "PUT" -> Color(0xFFFF9800)
    "DELETE" -> Color(0xFFF44336)
    "OPTIONS" -> Color(0xFF9C27B0)
    else -> Color.Gray
}

private fun statusColor(code: Int): Color = when (code) {
    in 200..299 -> Color(0xFF4CAF50)
    in 300..399 -> Color(0xFFFF9800)
    in 400..599 -> Color(0xFFF44336)
    else -> Color.Gray
}

private fun shortenUrl(url: String): String {
    return try {
        val u = java.net.URL(url)
        val path = u.path.ifEmpty { "/" }
        val query = u.query?.let { "?$it" } ?: ""
        path + query
    } catch (_: Exception) { url }
}

private fun formatBytes(bytes: Int): String = when {
    bytes < 1024 -> "${bytes}B"
    bytes < 1024 * 1024 -> "${bytes / 1024}KB"
    else -> String.format("%.1fMB", bytes / 1024.0 / 1024.0)
}
