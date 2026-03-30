package com.mollotov.browser.ui

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.spring
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectHorizontalDragGestures
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.FloatingActionButton
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
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
import androidx.compose.ui.draw.scale
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.Settings
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
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
 * - Opens a subtle blur overlay + fan-out menu items.
 *
 * @param contentModifier applied to the content layer behind the menu so blur can be toggled.
 */
@Composable
fun FloatingMenu(
    onReload: () -> Unit,
    onChromeAuth: () -> Unit,
    onSettings: () -> Unit,
    modifier: Modifier = Modifier,
) {
    var isOpen by remember { mutableStateOf(false) }
    /** 1 = right edge (default), -1 = left edge */
    var side by remember { mutableFloatStateOf(1f) }
    var dragOffsetPx by remember { mutableFloatStateOf(0f) }
    var containerWidthPx by remember { mutableFloatStateOf(0f) }
    var containerHeightPx by remember { mutableFloatStateOf(0f) }

    val density = LocalDensity.current
    val fabSizeDp = 44.dp
    val fabSizePx = with(density) { fabSizeDp.toPx() }
    val edgePaddingPx = with(density) { 16.dp.toPx() }
    val spreadRadius = 80f

    data class MenuItem(val label: String, val angle: Double, val action: () -> Unit, val iconName: String)

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
                    .blur(2.dp)
                    .background(Color.Black.copy(alpha = 0.15f))
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
            val step = 35.0
            return if (fanDirection < 0) {
                180.0 + step * index
            } else {
                360.0 - step * index
            }
        }

        val items = listOf(
            MenuItem("Reload", fanAngle(0), onReload, "refresh"),
            MenuItem("Chrome Login", fanAngle(1), onChromeAuth, "lock"),
            MenuItem("Settings", fanAngle(2), onSettings, "settings"),
        )

        // Fan-out items
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

            Column(
                horizontalAlignment = Alignment.CenterHorizontally,
                modifier = Modifier
                    .offset { IntOffset(fabOffsetX + dx, fabOffsetY + dy) }
                    .scale(scale)
                    .alpha(alpha),
            ) {
                FloatingActionButton(
                    onClick = {
                        item.action()
                        isOpen = false
                    },
                    containerColor = MollotovOrange,
                    contentColor = Color.White,
                    shape = CircleShape,
                    modifier = Modifier.size(44.dp),
                ) {
                    val icon: ImageVector = when (item.iconName) {
                        "refresh" -> Icons.Filled.Refresh
                        "lock" -> Icons.Filled.Lock
                        "settings" -> Icons.Filled.Settings
                        else -> Icons.Filled.Settings
                    }
                    Icon(imageVector = icon, contentDescription = item.label, modifier = Modifier.size(20.dp))
                }
                if (isOpen) {
                    Text(
                        text = item.label,
                        fontSize = 10.sp,
                        color = Color.White,
                        modifier = Modifier,
                    )
                }
            }
        }

        // Main FAB — flame icon, draggable horizontally
        val rotation by animateFloatAsState(
            targetValue = if (isOpen) 45f else 0f,
            animationSpec = spring(dampingRatio = 0.7f),
            label = "rotation",
        )
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
