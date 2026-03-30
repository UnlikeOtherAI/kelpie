package com.mollotov.browser.ui

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.spring
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material3.FloatingActionButton
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.draw.scale
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlin.math.cos
import kotlin.math.roundToInt
import kotlin.math.sin

/** App icon background color — warm peach/orange */
private val MollotovOrange = Color(244f / 255f, 176f / 255f, 120f / 255f)

@Composable
fun FloatingMenu(
    onReload: () -> Unit,
    onChromeAuth: () -> Unit,
    onSettings: () -> Unit,
    modifier: Modifier = Modifier,
) {
    var isOpen by remember { mutableStateOf(false) }
    val spreadRadius = 80f

    // Menu items: angle in degrees (180 = left, 270 = up)
    data class MenuItem(val icon: ImageVector, val label: String, val angle: Double, val action: () -> Unit)
    val items = listOf(
        MenuItem(Icons.Filled.Refresh, "Reload", 180.0, onReload),
        MenuItem(Icons.Filled.Lock, "Chrome Login", 215.0, onChromeAuth),
        MenuItem(Icons.Filled.Settings, "Settings", 250.0, onSettings),
    )

    Box(modifier = modifier.fillMaxSize()) {
        // Dim overlay
        if (isOpen) {
            Box(
                modifier = Modifier
                    .fillMaxSize()
                    .background(Color.Black.copy(alpha = 0.3f))
                    .clickable(
                        indication = null,
                        interactionSource = remember { MutableInteractionSource() },
                    ) { isOpen = false },
            )
        }

        // FAB + menu items
        Box(
            modifier = Modifier
                .align(Alignment.BottomEnd)
                .padding(end = 16.dp, bottom = 24.dp),
        ) {
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
                        .align(Alignment.BottomEnd)
                        .offset { IntOffset(dx, dy) }
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
                        Icon(item.icon, contentDescription = item.label, modifier = Modifier.size(20.dp))
                    }
                    if (isOpen) {
                        Text(
                            text = item.label,
                            fontSize = 10.sp,
                            color = Color.White,
                            modifier = Modifier.padding(top = 2.dp),
                        )
                    }
                }
            }

            // Main FAB
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
                    .size(36.dp)
                    .align(Alignment.BottomEnd)
                    .shadow(4.dp, CircleShape),
            ) {
                Icon(
                    Icons.Filled.Settings, // Using grid-like icon
                    contentDescription = "Menu",
                    modifier = Modifier
                        .size(18.dp)
                        .rotate(rotation),
                )
            }
        }
    }
}
