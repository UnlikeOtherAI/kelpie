package com.kelpie.browser.ui

import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Public
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Outline
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.kelpie.browser.browser.BrowserTab
import com.kelpie.browser.browser.ChromePalette

@Composable
fun TabletTabStrip(
    tabs: List<BrowserTab>,
    activeTabId: String?,
    color: Color,
    onAdd: () -> Unit,
    onSelect: (String) -> Unit,
    onClose: (String) -> Unit,
) {
    val list = rememberLazyListState()
    LaunchedEffect(activeTabId) {
        val index = tabs.indexOfFirst { it.id == activeTabId }
        if (index >= 0) list.animateScrollToItem(index)
    }
    Row(
        Modifier.fillMaxWidth().height(48.dp).background(Color(ChromePalette.GRAY)),
        verticalAlignment = Alignment.Bottom,
    ) {
        IconButton(onClick = onAdd, modifier = Modifier.size(48.dp)) {
            Icon(Icons.Default.Add, "New tab", tint = Color(ChromePalette.INK))
        }
        LazyRow(state = list, modifier = Modifier.weight(1f), verticalAlignment = Alignment.Bottom) {
            items(tabs, key = { it.id }) { tab ->
                val active = tab.id == activeTabId
                val background by animateColorAsState(if (active) color else Color(ChromePalette.GRAY), tween(200), label = "Tab colour")
                val foreground = Color(ChromePalette.foreground(if (active) tab.chromeColor else ChromePalette.GRAY))
                Row(Modifier.size(210.dp, 44.dp).clip(TabShoulders).background(background), verticalAlignment = Alignment.CenterVertically) {
                    Row(
                        Modifier
                            .weight(1f)
                            .height(44.dp)
                            .semantics { selected = active }
                            .clickable { onSelect(tab.id) }
                            .padding(start = 18.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Icon(Icons.Default.Public, null, Modifier.size(17.dp), tint = foreground)
                        Text(tabTitle(tab), Modifier.padding(start = 8.dp), color = foreground, fontSize = 13.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
                    }
                    IconButton(onClick = { onClose(tab.id) }, modifier = Modifier.size(44.dp)) {
                        Icon(Icons.Default.Close, "Close ${tabTitle(tab)}", Modifier.size(16.dp), tint = foreground)
                    }
                }
            }
        }
    }
}

private object TabShoulders : Shape {
    override fun createOutline(
        size: Size,
        layoutDirection: LayoutDirection,
        density: Density,
    ): Outline {
        val scale = size.height / 44f
        val w = size.width / scale
        val path =
            Path().apply {
                moveTo(0f, 44f)
                cubicTo(8f, 44f, 7f, 24f, 10f, 14f)
                quadraticBezierTo(12f, 0f, 25f, 0f)
                lineTo(w - 25f, 0f)
                quadraticBezierTo(w - 12f, 0f, w - 10f, 14f)
                cubicTo(w - 7f, 24f, w - 8f, 44f, w, 44f)
                close()
                transform(
                    androidx.compose.ui.graphics
                        .Matrix()
                        .apply { scale(scale, scale) },
                )
            }
        return Outline.Generic(path)
    }
}

internal fun tabTitle(tab: BrowserTab): String = if (tab.isStartPage) "Start Page" else tab.pageTitle.ifEmpty { domainFromUrl(tab.currentUrl) }

internal fun domainFromUrl(url: String): String =
    runCatching {
        java.net
            .URI(url)
            .host
            ?.removePrefix("www.")
    }.getOrNull() ?: "Start Page"
