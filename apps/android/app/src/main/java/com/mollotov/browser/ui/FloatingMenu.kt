package com.mollotov.browser.ui

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.spring
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
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
import androidx.compose.material3.Icon
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.blur
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.scale
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.input.pointer.positionChange
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import com.mollotov.browser.R
import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.roundToInt
import kotlin.math.sin
import androidx.compose.foundation.gestures.awaitEachGesture

/** App icon background color — warm peach/orange */
private val MollotovOrange = Color(244f / 255f, 176f / 255f, 120f / 255f)

/**
 * Floating action button that expands into a fan menu.
 * - 44dp circular FAB with flame icon, vertically centered on the right edge.
 * - Horizontally draggable between left and right sides of the screen.
 * - Opens a blur overlay + fan-out menu items (no labels, wider spread).
 * - Menu items are clamped to stay within screen bounds.
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
    val menuItemSizePx = fabSizePx
    val spreadRadius = 120f
    val dragThreshold = 10f

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
            val halfArc = step * 2.5 // 75 degrees
            val center = if (fanDirection < 0) 180.0 else 0.0
            return center - halfArc + step * index
        }

        val items = listOf(
            MenuItem(fanAngle(0), onReload, "refresh"),
            MenuItem(fanAngle(1), onChromeAuth, "lock"),
            MenuItem(fanAngle(2), onBookmarks, "bookmark"),
            MenuItem(fanAngle(3), onHistory, "history"),
            MenuItem(fanAngle(4), onNetworkInspector, "network"),
            MenuItem(fanAngle(5), onSettings, "settings"),
        )

        // Fan-out items with screen-bound clamping
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
            val rawDx = if (isOpen) (cos(angleRad) * spreadRadius).toFloat() else 0f
            val rawDy = if (isOpen) (sin(angleRad) * spreadRadius).toFloat() else 0f

            // Clamp so items never leave the screen
            val margin = menuItemSizePx / 2 + edgePaddingPx
            val minDx = margin - clampedX
            val maxDx = containerWidthPx - margin - clampedX
            val minDy = margin - midY
            val maxDy = containerHeightPx - margin - midY
            val dx = rawDx.coerceIn(minDx, maxDx).roundToInt()
            val dy = rawDy.coerceIn(minDy, maxDy).roundToInt()

            Box(
                contentAlignment = Alignment.Center,
                modifier = Modifier
                    .size(44.dp)
                    .offset { IntOffset(fabOffsetX + dx, fabOffsetY + dy) }
                    .scale(scale)
                    .alpha(alpha)
                    .shadow(3.dp, CircleShape)
                    .clip(CircleShape)
                    .background(MollotovOrange)
                    .clickable {
                        item.action()
                        isOpen = false
                    },
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
                Icon(imageVector = icon, contentDescription = item.iconName, modifier = Modifier.size(20.dp), tint = Color.White)
            }
        }

        // Main FAB — flame icon, custom gesture handles both tap and drag
        Box(
            contentAlignment = Alignment.Center,
            modifier = Modifier
                .size(fabSizeDp)
                .offset { IntOffset(fabOffsetX, fabOffsetY) }
                .shadow(4.dp, CircleShape)
                .clip(CircleShape)
                .background(MollotovOrange)
                .pointerInput(Unit) {
                    awaitEachGesture {
                        // Wait for the initial down event
                        val downEvent = awaitPointerEvent()
                        val downChange = downEvent.changes.firstOrNull() ?: return@awaitEachGesture
                        val startX = downChange.position.x
                        var dragging = false

                        do {
                            val event = awaitPointerEvent()
                            val change = event.changes.firstOrNull() ?: break
                            if (!change.pressed) {
                                // Finger lifted
                                change.consume()
                                if (dragging) {
                                    val finalX = (baseX + dragOffsetPx).coerceIn(leftX, rightX)
                                    val screenMid = containerWidthPx / 2
                                    side = if (finalX < screenMid) -1f else 1f
                                    dragOffsetPx = 0f
                                } else {
                                    isOpen = !isOpen
                                }
                                break
                            }
                            val dx = change.position.x - startX
                            if (abs(dx) > dragThreshold) {
                                dragging = true
                                dragOffsetPx = dx
                                change.consume()
                            }
                        } while (true)
                    }
                },
        ) {
            Icon(
                painter = painterResource(id = R.drawable.ic_launcher_foreground),
                contentDescription = "Menu",
                modifier = Modifier.size(36.dp),
                tint = Color.White,
            )
        }
    }
}
