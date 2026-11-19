package com.kelpie.browser.ui

import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.tween
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawWithCache
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.PathMeasure
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.unit.dp

@Composable
internal fun addressLoadOutline(
    tabId: String?,
    isLoading: Boolean,
    progress: Float,
): Modifier {
    val extent = remember(tabId) { Animatable(0f) }
    val opacity = remember(tabId) { Animatable(0f) }
    LaunchedEffect(tabId, isLoading, progress) {
        if (isLoading) {
            if (opacity.targetValue == 0f || progress < extent.targetValue - 0.15f) {
                extent.snapTo(0.005f)
            }
            opacity.snapTo(1f)
            extent.animateTo(progress.coerceIn(0.005f, 1f), tween(120))
        } else if (opacity.value == 1f) {
            if (progress >= 1f) extent.animateTo(1f, tween(120))
            opacity.animateTo(0f, tween(200))
        } else if (opacity.value > 0f) {
            opacity.animateTo(0f, tween(200))
        }
    }
    return Modifier.drawWithCache {
        val width = 3.dp.toPx()
        val inset = width / 2
        val radius = (minOf(size.width, size.height) / 2 - inset).coerceAtLeast(0f)
        val centerY = size.height / 2
        val left = Rect(inset, centerY - radius, inset + 2 * radius, centerY + radius)
        val right = Rect(size.width - inset - 2 * radius, left.top, size.width - inset, left.bottom)
        val outline =
            Path().apply {
                arcTo(right, 0f, -90f, true)
                arcTo(left, -90f, -180f, false)
                arcTo(right, 90f, -90f, false)
            }
        val measure = PathMeasure().apply { setPath(outline, false) }
        val visible = Path()
        val stroke = Stroke(width = width, cap = StrokeCap.Round)
        onDrawWithContent {
            drawContent()
            if (radius > 0f && opacity.value > 0f) {
                val half = extent.value / 2
                visible.reset()
                measure.getSegment(measure.length * (0.5f - half), measure.length * (0.5f + half), visible)
                drawPath(visible, Color(0xFF007AFF), alpha = opacity.value, style = stroke)
            }
        }
    }
}
