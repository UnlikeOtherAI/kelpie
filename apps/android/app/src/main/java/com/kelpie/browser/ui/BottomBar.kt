package com.kelpie.browser.ui

import androidx.compose.animation.core.animateDpAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectVerticalDragGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.ArrowForward
import androidx.compose.material.icons.filled.Bookmarks
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.MoreHoriz
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

enum class ScrollDirection { UP, DOWN }

/** One bottom navigation surface; tab management lives above the page or in overview. */
@Composable
fun BottomBar(
    currentUrl: String,
    canGoBack: Boolean,
    canGoForward: Boolean,
    isLoading: Boolean,
    isCollapsed: Boolean,
    onNavigate: (String) -> Unit,
    onBack: () -> Unit,
    onForward: () -> Unit,
    onReload: () -> Unit,
    onBookmarks: () -> Unit,
    onShowTabs: () -> Unit,
    onExpand: () -> Unit,
    moreContent: @Composable ColumnScope.(() -> Unit) -> Unit,
) {
    var editing by remember { mutableStateOf(false) }
    var more by remember { mutableStateOf(false) }
    val compact = isCollapsed && !editing && !more
    val height by animateDpAsState(if (compact) 34.dp else 62.dp, tween(250), label = "Toolbar height")
    val focus = LocalFocusManager.current
    val density = LocalDensity.current.density
    Surface(color = MaterialTheme.colorScheme.surface.copy(alpha = 0.96f), shape = RoundedCornerShape(topStart = 28.dp, topEnd = 28.dp)) {
        BoxWithConstraints(Modifier.fillMaxWidth().height(height)) {
            val wide = maxWidth >= 600.dp
            Row(
                Modifier.fillMaxSize().padding(horizontal = 8.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(4.dp),
            ) {
                if (!compact && !editing) {
                    ChromeButton(Icons.AutoMirrored.Filled.ArrowBack, "Back", canGoBack, onBack)
                    ChromeButton(Icons.AutoMirrored.Filled.ArrowForward, "Forward", canGoForward, onForward)
                }
                if (compact) Spacer(Modifier.weight(1f))
                Box(
                    Modifier
                        .then(if (compact) Modifier.widthIn(max = 180.dp) else Modifier.weight(1f))
                        .pointerInput(editing) {
                            if (!editing) {
                                var drag = 0f
                                detectVerticalDragGestures(onDragStart = { drag = 0f }, onVerticalDrag = { change, amount ->
                                    drag += amount
                                    change.consume()
                                }, onDragEnd = { if (drag < -32 * density) onShowTabs() })
                            }
                        },
                ) {
                    if (compact) {
                        Text(
                            domainFromUrl(currentUrl),
                            Modifier
                                .clip(CircleShape)
                                .background(MaterialTheme.colorScheme.surfaceVariant)
                                .clickable(onClick = onExpand)
                                .padding(horizontal = 16.dp, vertical = 5.dp),
                            fontSize = 12.sp,
                            maxLines = 1,
                        )
                    } else {
                        HistoryAutocompleteField(
                            currentUrl,
                            "Search or enter address",
                            {
                                focus.clearFocus()
                                editing = false
                                onNavigate(it)
                            },
                            Modifier.fillMaxWidth().height(44.dp),
                            shape = CircleShape,
                            textStyle = MaterialTheme.typography.bodySmall,
                            onEditingChanged = {
                                editing = it
                                if (it) onExpand()
                            },
                            trailingIcon = {
                                if (!editing) {
                                    IconButton(onClick = onReload, modifier = Modifier.size(40.dp)) {
                                        Icon(
                                            if (isLoading) Icons.Default.Close else Icons.Default.Refresh,
                                            if (isLoading) "Stop loading" else "Reload",
                                            Modifier.size(18.dp),
                                        )
                                    }
                                }
                            },
                        )
                    }
                }
                if (compact) Spacer(Modifier.weight(1f))
                if (!compact) {
                    if (editing) {
                        TextButton(onClick = {
                            focus.clearFocus()
                            editing = false
                        }) { Text("Cancel") }
                    } else {
                        if (wide) ChromeButton(Icons.Default.Bookmarks, "Bookmarks", action = onBookmarks)
                        Box {
                            ChromeButton(Icons.Default.MoreHoriz, "More", action = {
                                onExpand()
                                more = true
                            })
                            DropdownMenu(expanded = more, onDismissRequest = { more = false }) {
                                moreContent { more = false }
                            }
                        }
                    }
                }
            }
        }
    }
}

@Composable
internal fun ChromeButton(
    icon: ImageVector,
    label: String,
    enabled: Boolean = true,
    action: () -> Unit,
) {
    IconButton(onClick = action, enabled = enabled, modifier = Modifier.size(44.dp).background(MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.6f), CircleShape)) {
        Icon(icon, label, Modifier.size(20.dp))
    }
}
