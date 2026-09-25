package com.kelpie.browser.ui

import androidx.compose.runtime.setValue
import androidx.compose.runtime.getValue
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectHorizontalDragGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Public
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import androidx.compose.ui.text.style.TextOverflow
import com.kelpie.browser.browser.BrowserTab
import kotlin.math.abs
import kotlin.math.roundToInt

@Composable
internal fun BrowserTabOverview(tabs: List<BrowserTab>, activeId: String?, onSelect: (String) -> Unit,
    onClose: (String) -> Unit, onAdd: () -> Unit, onDismiss: () -> Unit) {
    Column(Modifier.fillMaxWidth().fillMaxHeight(0.95f)) {
        Row(Modifier.fillMaxWidth().padding(horizontal = 20.dp), verticalAlignment = Alignment.CenterVertically) {
            Text(if (tabs.size == 1) "1 Tab" else "${tabs.size} Tabs", style = MaterialTheme.typography.titleLarge)
            Spacer(Modifier.weight(1f))
            TextButton(onClick = onDismiss) { Text("Done") }
        }
        LazyVerticalGrid(columns = GridCells.Fixed(2), modifier = Modifier.weight(1f),
            contentPadding = PaddingValues(16.dp), horizontalArrangement = Arrangement.spacedBy(16.dp), verticalArrangement = Arrangement.spacedBy(20.dp)) {
            items(tabs, key = { it.id }) { tab ->
                TabPreview(tab, tab.id == activeId, { onSelect(tab.id) }, { onClose(tab.id) })
            }
        }
        TextButton(onClick = onAdd, modifier = Modifier.fillMaxWidth().height(48.dp)) { Text("+  New tab") }
    }
}

@Composable
private fun TabPreview(tab: BrowserTab, selected: Boolean, onSelect: () -> Unit, onClose: () -> Unit) {
    var drag by remember { mutableFloatStateOf(0f) }
    val density = LocalDensity.current.density
    val shape = RoundedCornerShape(18.dp)
    Column(Modifier.offset { IntOffset(drag.roundToInt(), 0) }.clip(shape)
        .background(MaterialTheme.colorScheme.surfaceVariant)
        .border(if (selected) 3.dp else 0.dp, if (selected) MaterialTheme.colorScheme.primary else androidx.compose.ui.graphics.Color.Transparent, shape)
        .pointerInput(tab.id) {
            detectHorizontalDragGestures(onHorizontalDrag = { change, amount -> drag += amount; change.consume() },
                onDragEnd = { if (abs(drag) > 80 * density) onClose(); drag = 0f }, onDragCancel = { drag = 0f })
        }) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(tabTitle(tab), Modifier.weight(1f).padding(start = 12.dp), maxLines = 1, overflow = TextOverflow.Ellipsis)
            IconButton(onClick = onClose, modifier = Modifier.size(44.dp)) { Icon(Icons.Default.Close, "Close tab", Modifier.size(16.dp)) }
        }
        Box(Modifier.fillMaxWidth().aspectRatio(0.7f).clickable(onClick = onSelect), contentAlignment = Alignment.Center) {
            val preview = tab.preview
            if (preview != null) Image(preview.asImageBitmap(), "Open ${tabTitle(tab)}", Modifier.fillMaxSize(), contentScale = ContentScale.Crop, alignment = Alignment.TopCenter)
            else Column(horizontalAlignment = Alignment.CenterHorizontally) {
                Icon(Icons.Default.Public, "Open ${tabTitle(tab)}", Modifier.size(36.dp))
                Text(domainFromUrl(tab.currentUrl), Modifier.padding(12.dp), maxLines = 2)
            }
        }
    }
}
