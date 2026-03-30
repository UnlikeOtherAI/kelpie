package com.mollotov.browser.ui

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.spring
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectHorizontalDragGestures
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Favorite
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.automirrored.filled.List
import androidx.compose.material.icons.filled.Info
import androidx.compose.material3.FloatingActionButton
import androidx.compose.material3.Icon
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.blur
import androidx.compose.ui.draw.scale
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import com.mollotov.browser.R
import kotlin.math.cos
import kotlin.math.roundToInt
import kotlin.math.sin

/** App icon background color — warm peach/orange */
private val MollotovOrange = Color(244f / 255f, 176f / 255f, 120f / 255f)

/**
 * Floating action button that expands into a fan menu.
 * - 44dp circular FAB with flame icon, vertically centered on the right edge.
 * - Horizontally draggable between left and right sides of the screen.
 * - Opens a blur overlay + fan-out menu items (no labels, wider spread).
 */
@Composable
fun FloatingMenu(
    onReload: () -> Unit,
    onChromeAuth: () -> Unit,
    onSettings: () -> Unit,
    onBookmarks: () -> Unit,
    onHistory: () -> Unit,
    onNetworkInspector: () -> Unit,
    modifier: Modifier = Modifier,
) {
    var isOpen by remember { mutableStateOf(false) }
    var side by remember { mutableFloatStateOf(1f) }
    var dragOffsetPx by remember { mutableFloatStateOf(0f) }
    var containerWidthPx by remember { mutableFloatStateOf(0f) }
    var containerHeightPx by remember { mutableFloatStateOf(0f) }

    val density = LocalDensity.current
    val fabSizeDp = 44.dp
    val fabSizePx = with(density) { fabSizeDp.toPx() }
    val edgePaddingPx = with(density) { 16.dp.toPx() }
    val spreadRadius = 120f

    data class MenuItem(val angle: Double, val action: () -> Unit, val iconName: String)

    Box(
        modifier = modifier
            .fillMaxSize()
            .onGloballyPositioned { coords ->
                containerWidthPx = coords.size.width.toFloat()
                containerHeightPx = coords.size.height.toFloat()
            },
    ) {
        // Blur + dim overlay when menu is open
        if (isOpen) {
            Box(
                modifier = Modifier
                    .fillMaxSize()
                    .blur(6.dp)
                    .background(Color.Black.copy(alpha = 0.25f))
                    .clickable(
                        indication = null,
                        interactionSource = remember { MutableInteractionSource() },
                    ) { isOpen = false },
            )
        }

        // Compute FAB position
        val rightX = containerWidthPx - edgePaddingPx - fabSizePx / 2
        val leftX = edgePaddingPx + fabSizePx / 2
        val baseX = if (side > 0) rightX else leftX
        val clampedX = (baseX + dragOffsetPx).coerceIn(leftX, rightX)
        val midY = containerHeightPx / 2

        val fabOffsetX = (clampedX - fabSizePx / 2).roundToInt()
        val fabOffsetY = (midY - fabSizePx / 2).roundToInt()

        // Fan direction: items fan away from the current edge
        val fanDirection = if (side > 0) -1.0 else 1.0

        fun fanAngle(index: Int): Double {
            val step = 30.0
            return if (fanDirection < 0) {
                150.0 + step * index
            } else {
                390.0 - step * index
            }
        }

        val items = listOf(
            MenuItem(fanAngle(0), onReload, "refresh"),
            MenuItem(fanAngle(1), onChromeAuth, "lock"),
            MenuItem(fanAngle(2), onBookmarks, "bookmark"),
            MenuItem(fanAngle(3), onHistory, "history"),
            MenuItem(fanAngle(4), onNetworkInspector, "network"),
            MenuItem(fanAngle(5), onSettings, "settings"),
        )

        // Fan-out items (no labels)
        items.forEach { item ->
            val scale by animateFloatAsState(
                targetValue = if (isOpen) 1f else 0.3f,
                animationSpec = spring(dampingRatio = 0.7f),
                label = "scale",
            )
            val alpha by animateFloatAsState(
                targetValue = if (isOpen) 1f else 0f,
                animationSpec = spring(dampingRatio = 0.7f),
                label = "alpha",
            )
            val angleRad = Math.toRadians(item.angle)
            val dx = if (isOpen) (cos(angleRad) * spreadRadius).roundToInt() else 0
            val dy = if (isOpen) (sin(angleRad) * spreadRadius).roundToInt() else 0

            FloatingActionButton(
                onClick = {
                    item.action()
                    isOpen = false
                },
                containerColor = MollotovOrange,
                contentColor = Color.White,
                shape = CircleShape,
                modifier = Modifier
                    .size(44.dp)
                    .offset { IntOffset(fabOffsetX + dx, fabOffsetY + dy) }
                    .scale(scale)
                    .alpha(alpha),
            ) {
                val icon: ImageVector = when (item.iconName) {
                    "refresh" -> Icons.Filled.Refresh
                    "lock" -> Icons.Filled.Lock
                    "bookmark" -> Icons.Filled.Favorite
                    "history" -> Icons.AutoMirrored.Filled.List
                    "network" -> Icons.Filled.Info
                    "settings" -> Icons.Filled.Settings
                    else -> Icons.Filled.Settings
                }
                Icon(imageVector = icon, contentDescription = item.iconName, modifier = Modifier.size(20.dp))
            }
        }

        // Main FAB — flame icon, draggable horizontally
        FloatingActionButton(
            onClick = { isOpen = !isOpen },
            containerColor = MollotovOrange,
            contentColor = Color.White,
            shape = CircleShape,
            modifier = Modifier
                .size(fabSizeDp)
                .offset { IntOffset(fabOffsetX, fabOffsetY) }
                .shadow(4.dp, CircleShape)
                .pointerInput(Unit) {
                    detectHorizontalDragGestures(
                        onHorizontalDrag = { _, dragAmount ->
                            dragOffsetPx += dragAmount
                        },
                        onDragEnd = {
                            val finalX = (baseX + dragOffsetPx).coerceIn(leftX, rightX)
                            val screenMid = containerWidthPx / 2
                            side = if (finalX < screenMid) -1f else 1f
                            dragOffsetPx = 0f
                        },
                    )
                },
        ) {
            Icon(
                painter = painterResource(id = R.drawable.ic_launcher_foreground),
                contentDescription = "Menu",
                modifier = Modifier.size(36.dp),
            )
        }
    }
}
