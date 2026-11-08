package com.kelpie.browser.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.PanTool
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.SwapVert
import androidx.compose.material.icons.filled.ZoomIn
import androidx.compose.material.icons.filled.ZoomOut
import androidx.compose.material3.Icon
import androidx.compose.material3.LocalContentColor
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp

@Composable
fun Inspector3DControlsBar(
    mode: String,
    onSelectMode: (String) -> Unit,
    onZoomOut: () -> Unit,
    onZoomIn: () -> Unit,
    onReset: () -> Unit,
    onExit: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Surface(
        modifier = modifier,
        shape = RoundedCornerShape(24.dp),
        tonalElevation = 6.dp,
        shadowElevation = 8.dp,
        color = MaterialTheme.colorScheme.surface.copy(alpha = 0.96f),
    ) {
        Row(
            horizontalArrangement = Arrangement.spacedBy(10.dp),
            modifier = Modifier.padding(horizontal = 12.dp, vertical = 10.dp),
        ) {
            modeButton(
                selected = mode == "rotate",
                icon = { Icon(Icons.Filled.PanTool, contentDescription = "Rotate mode") },
                onClick = { onSelectMode("rotate") },
            )
            modeButton(
                selected = mode == "scroll",
                icon = { Icon(Icons.Filled.SwapVert, contentDescription = "Scroll mode") },
                onClick = { onSelectMode("scroll") },
            )
            controlButton(
                icon = { Icon(Icons.Filled.ZoomOut, contentDescription = "Zoom out 3D view") },
                onClick = onZoomOut,
            )
            controlButton(
                icon = { Icon(Icons.Filled.ZoomIn, contentDescription = "Zoom in 3D view") },
                onClick = onZoomIn,
            )
            controlButton(
                icon = { Icon(Icons.Filled.Refresh, contentDescription = "Reset 3D view") },
                onClick = onReset,
            )
            controlButton(
                icon = { Icon(Icons.Filled.Close, contentDescription = "Exit 3D view") },
                onClick = onExit,
            )
        }
    }
}

@Composable
private fun modeButton(
    selected: Boolean,
    icon: @Composable () -> Unit,
    onClick: () -> Unit,
) {
    val background = if (selected) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.surfaceVariant
    val tint = if (selected) MaterialTheme.colorScheme.onPrimary else MaterialTheme.colorScheme.onSurfaceVariant
    BoxIconButton(
        background = background,
        tint = tint,
        onClick = onClick,
        icon = icon,
    )
}

@Composable
private fun controlButton(
    icon: @Composable () -> Unit,
    onClick: () -> Unit,
) {
    BoxIconButton(
        background = MaterialTheme.colorScheme.surfaceVariant,
        tint = MaterialTheme.colorScheme.onSurfaceVariant,
        onClick = onClick,
        icon = icon,
    )
}

@Composable
private fun BoxIconButton(
    background: Color,
    tint: Color,
    onClick: () -> Unit,
    icon: @Composable () -> Unit,
) {
    Box(
        contentAlignment = Alignment.Center,
        modifier =
            Modifier
                .size(36.dp)
                .clip(CircleShape)
                .background(background)
                .border(1.dp, MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.7f), CircleShape)
                .clickable(onClick = onClick)
                .padding(8.dp),
    ) {
        CompositionLocalProvider(LocalContentColor provides tint) {
            icon()
        }
    }
}
