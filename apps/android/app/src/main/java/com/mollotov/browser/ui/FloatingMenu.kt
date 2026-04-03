package com.mollotov.browser.ui

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.spring
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Favorite
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material.icons.filled.PhoneIphone
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.automirrored.filled.List
import androidx.compose.material.icons.filled.Info
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
import androidx.compose.ui.draw.clip
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
import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.roundToInt
import kotlin.math.sin
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp

/** App icon background color — warm peach/orange */
private val MollotovOrange = Color(244f / 255f, 176f / 255f, 120f / 255f)
/** Richer menu item color — more red/saturated for contrast against the FAB */
private val MenuItemOrange = Color(240f / 255f, 148f / 255f, 90f / 255f)

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
    onAI: () -> Unit,
    onSnapshot3D: () -> Unit,
    show3DInspector: Boolean,
    showMobileViewportToggle: Boolean,
    mobileViewportPresets: List<TabletViewportPreset>,
    selectedMobileViewportPresetId: String?,
    onSelectMobileViewportPreset: (String) -> Unit,
    modifier: Modifier = Modifier,
) {
    var isOpen by remember { mutableStateOf(false) }
    var isMobileViewportPickerOpen by remember { mutableStateOf(false) }
    var side by remember { mutableFloatStateOf(1f) }
    var dragOffsetPx by remember { mutableFloatStateOf(0f) }
    var containerWidthPx by remember { mutableFloatStateOf(0f) }
    var containerHeightPx by remember { mutableFloatStateOf(0f) }

    val density = LocalDensity.current
    val fabSizeDp = 44.dp
    val pillWidthDp = 168.dp
    val pillHeightDp = 36.dp
    val fabSizePx = with(density) { fabSizeDp.toPx() }
    val edgePaddingPx = with(density) { 16.dp.toPx() }
    val menuItemSizePx = fabSizePx
    val baseSpreadRadius = 150f
    val minimumMenuItemGapPx = with(density) { 12.dp.toPx() }
    val dragThreshold = 10f
    val pillWidthPx = with(density) { pillWidthDp.toPx() }
    val pillHeightPx = with(density) { pillHeightDp.toPx() }
    val pillLaneSpacingPx = with(density) { 34.dp.toPx() }
    val pillStackSpacingPx = with(density) { 10.dp.toPx() }

    data class MenuItem(
        val id: String,
        val action: () -> Unit,
        val iconName: String,
        val tint: Color = Color.White,
        val background: Color = MenuItemOrange,
        val border: Color = Color.Transparent,
        val closesMenu: Boolean = true,
    )

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
                    ) {
                        isOpen = false
                        isMobileViewportPickerOpen = false
                    },
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

        fun fanAngle(index: Int, itemCount: Int): Double {
            val center = if (fanDirection < 0) 180.0 else 0.0
            if (itemCount <= 1) return center
            val step = 180.0 / (itemCount - 1)
            return center - 90.0 + step * index
        }

        fun spreadRadius(itemCount: Int): Float {
            if (itemCount <= 1) return baseSpreadRadius

            val stepRadians = Math.PI / (itemCount - 1).toDouble()
            val minimumCenterDistance = menuItemSizePx + minimumMenuItemGapPx
            val requiredRadius = (minimumCenterDistance / (2 * sin(stepRadians / 2))).toFloat()
            return maxOf(baseSpreadRadius, requiredRadius)
        }

        fun menuItemOffset(index: Int, itemCount: Int): IntOffset {
            val angleRad = Math.toRadians(fanAngle(index, itemCount))
            val spreadRadius = spreadRadius(itemCount)
            val rawDx = if (isOpen) (cos(angleRad) * spreadRadius).toFloat() else 0f
            val rawDy = if (isOpen) (sin(angleRad) * spreadRadius).toFloat() else 0f
            val margin = menuItemSizePx / 2 + edgePaddingPx
            val minDx = margin - clampedX
            val maxDx = containerWidthPx - margin - clampedX
            val minDy = margin - midY
            val maxDy = containerHeightPx - margin - midY
            val dx = rawDx.coerceIn(minDx, maxDx).roundToInt()
            val dy = rawDy.coerceIn(minDy, maxDy).roundToInt()
            return IntOffset(dx, dy)
        }

        val rawItems = buildList {
            add(MenuItem(id = "browser.menu.reload", action = onReload, iconName = "refresh"))
            add(MenuItem(id = "browser.menu.safari-auth", action = onChromeAuth, iconName = "lock"))
            if (showMobileViewportToggle) {
                add(
                    MenuItem(
                        id = "browser.viewport.mobile-toggle",
                        action = {
                            if (mobileViewportPresets.isNotEmpty()) {
                                isMobileViewportPickerOpen = !isMobileViewportPickerOpen
                            }
                        },
                        iconName = "mobile",
                        tint = Color.White,
                        background = if (selectedMobileViewportPresetId != null || isMobileViewportPickerOpen) MollotovOrange else MenuItemOrange,
                        border = if (selectedMobileViewportPresetId != null || isMobileViewportPickerOpen) Color.White.copy(alpha = 0.9f) else Color.Transparent,
                        closesMenu = false,
                    ),
                )
            }
            add(MenuItem(id = "browser.menu.bookmarks", action = onBookmarks, iconName = "bookmark"))
            add(MenuItem(id = "browser.menu.history", action = onHistory, iconName = "history"))
            add(MenuItem(id = "browser.menu.network-inspector", action = onNetworkInspector, iconName = "network"))
            add(MenuItem(id = "browser.menu.ai", action = onAI, iconName = "ai"))
            if (show3DInspector) {
                add(MenuItem(id = "browser.menu.snapshot-3d", action = onSnapshot3D, iconName = "snapshot3d"))
            }
            add(MenuItem(id = "browser.menu.settings", action = onSettings, iconName = "settings"))
        }
        val items = rawItems

        // Fan-out items with screen-bound clamping
        items.forEachIndexed { index, item ->
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
            val itemOffset = menuItemOffset(index = index, itemCount = items.size)

            Box(
                contentAlignment = Alignment.Center,
                modifier = Modifier
                    .size(44.dp)
                    .offset { IntOffset(fabOffsetX + itemOffset.x, fabOffsetY + itemOffset.y) }
                    .scale(scale)
                    .alpha(alpha)
                    .shadow(3.dp, CircleShape)
                    .clip(CircleShape)
                    .background(item.background)
                    .border(
                        width = if (item.border == Color.Transparent) 0.dp else 1.5.dp,
                        color = item.border,
                        shape = CircleShape,
                    )
                    .clickable {
                        item.action()
                        if (item.closesMenu) {
                            isOpen = false
                            isMobileViewportPickerOpen = false
                        }
                    },
            ) {
                val icon: ImageVector? = when (item.iconName) {
                    "refresh" -> Icons.Filled.Refresh
                    "lock" -> Icons.Filled.Lock
                    "mobile" -> Icons.Filled.PhoneIphone
                    "bookmark" -> Icons.Filled.Favorite
                    "history" -> Icons.AutoMirrored.Filled.List
                    "network" -> Icons.Filled.Info
                    "settings" -> Icons.Filled.Settings
                    else -> null
                }
                if (icon != null) {
                    Icon(imageVector = icon, contentDescription = item.iconName, modifier = Modifier.size(20.dp), tint = item.tint)
                } else {
                    Text(
                        text = if (item.iconName == "snapshot3d") "3D" else "AI",
                        color = item.tint,
                        fontWeight = FontWeight.Bold,
                    )
                }
            }
        }

        if (showMobileViewportToggle && isMobileViewportPickerOpen) {
            val mobileIndex = items.indexOfFirst { it.id == "browser.viewport.mobile-toggle" }
            if (mobileIndex >= 0) {
                val anchorOffset = menuItemOffset(index = mobileIndex, itemCount = items.size)
                val anchorX = clampedX + anchorOffset.x + fabSizePx / 2
                val anchorY = midY + anchorOffset.y + fabSizePx / 2
                val rowSpacingPx = pillHeightPx + pillStackSpacingPx
                val baseOffsetPx = menuItemSizePx / 2 + pillHeightPx / 2 + pillStackSpacingPx
                val pillBaseX = anchorX + (fanDirection.toFloat() * (menuItemSizePx / 2 + pillWidthPx / 2 + pillLaneSpacingPx))
                val upwardStartY = anchorY - baseOffsetPx
                val downwardStartY = anchorY + baseOffsetPx
                val minCenterY = edgePaddingPx + pillHeightPx / 2
                val maxCenterY = containerHeightPx - edgePaddingPx - pillHeightPx / 2
                val upwardCapacity = maxOf(kotlin.math.floor((upwardStartY - minCenterY) / rowSpacingPx).toInt() + 1, 1)
                val downwardCapacity = maxOf(kotlin.math.floor((maxCenterY - downwardStartY) / rowSpacingPx).toInt() + 1, 1)
                val stackDirection = if (downwardCapacity >= upwardCapacity) 1f else -1f
                val startY = if (stackDirection > 0f) downwardStartY else upwardStartY
                val rowsPerColumn = maxOf(if (stackDirection > 0f) downwardCapacity else upwardCapacity, 1)
                val columnSpacingPx = pillWidthPx + with(density) { 12.dp.toPx() }

                mobileViewportPresets.forEachIndexed { index, preset ->
                    val row = index % rowsPerColumn
                    val column = index / rowsPerColumn
                    val rawY = startY + (stackDirection * row.toFloat() * rowSpacingPx)
                    val rawX = pillBaseX + (fanDirection.toFloat() * column.toFloat() * columnSpacingPx)
                    val clampedPillX = rawX.coerceIn(
                        pillWidthPx / 2 + edgePaddingPx,
                        containerWidthPx - pillWidthPx / 2 - edgePaddingPx,
                    )
                    val clampedPillY = rawY.coerceIn(
                        pillHeightPx / 2 + edgePaddingPx,
                        containerHeightPx - pillHeightPx / 2 - edgePaddingPx,
                    )
                    val isSelected = preset.id == selectedMobileViewportPresetId
                    val scale by animateFloatAsState(
                        targetValue = if (isMobileViewportPickerOpen) 1f else 0.85f,
                        animationSpec = spring(dampingRatio = 0.8f),
                        label = "mobile-pill-scale-${preset.id}",
                    )
                    val alpha by animateFloatAsState(
                        targetValue = if (isMobileViewportPickerOpen) 1f else 0f,
                        animationSpec = spring(dampingRatio = 0.8f),
                        label = "mobile-pill-alpha-${preset.id}",
                    )

                    Box(
                        contentAlignment = Alignment.Center,
                        modifier = Modifier
                            .size(width = pillWidthDp, height = pillHeightDp)
                            .offset {
                                IntOffset(
                                    (clampedPillX - pillWidthPx / 2).roundToInt(),
                                    (clampedPillY - pillHeightPx / 2).roundToInt(),
                                )
                            }
                            .scale(scale)
                            .alpha(alpha)
                            .shadow(6.dp, RoundedCornerShape(18.dp))
                            .clip(RoundedCornerShape(18.dp))
                            .background(if (isSelected) MollotovOrange else MenuItemOrange)
                            .border(
                                width = if (isSelected) 1.5.dp else 1.dp,
                                color = Color.White.copy(alpha = if (isSelected) 0.9f else 0.35f),
                                shape = RoundedCornerShape(18.dp),
                            )
                            .clickable {
                                onSelectMobileViewportPreset(preset.id)
                                isMobileViewportPickerOpen = false
                                isOpen = false
                            },
                    ) {
                        Text(
                            text = preset.menuLabel,
                            color = Color.White,
                            fontWeight = FontWeight.SemiBold,
                            maxLines = 1,
                        )
                    }
                }
            }
        }

        // Main FAB — flame icon, custom gesture handles both tap and drag
        Box(
            contentAlignment = Alignment.Center,
            modifier = Modifier
                .size(fabSizeDp)
                .offset { IntOffset(fabOffsetX, fabOffsetY) }
                .shadow(4.dp, CircleShape)
                .alpha(if (isOpen) 0.8f else 1f)
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
                                    if (isOpen) {
                                        isMobileViewportPickerOpen = false
                                    }
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
