package com.kelpie.browser.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

@Composable
internal fun TabletViewportStage(
    preset: TabletViewportPreset,
    stageSize: Pair<Dp, Dp>,
    onClose: () -> Unit,
    content: @Composable () -> Unit,
) {
    Column(
        modifier =
            Modifier
                .size(stageSize.first, stageSize.second + 48.dp),
    ) {
        Box(
            modifier =
                Modifier
                    .fillMaxWidth()
                    .size(height = 38.dp, width = stageSize.first),
        ) {
            Text(
                text = "${preset.displaySizeLabel} • ${preset.pixelResolutionLabel}",
                color = Color.White,
                fontSize = 11.sp,
                modifier =
                    Modifier
                        .align(Alignment.Center)
                        .clip(RoundedCornerShape(18.dp))
                        .background(Color.Black.copy(alpha = 0.9f))
                        .border(1.dp, Color.White.copy(alpha = 0.9f), RoundedCornerShape(18.dp))
                        .padding(horizontal = 14.dp, vertical = 8.dp),
            )

            Row(
                modifier =
                    Modifier
                        .fillMaxSize()
                        .padding(start = 0.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Box(
                    contentAlignment = Alignment.Center,
                    modifier =
                        Modifier
                            .size(34.dp)
                            .clip(CircleShape)
                            .background(Color.Black.copy(alpha = 0.9f))
                            .border(1.dp, Color.White.copy(alpha = 0.9f), CircleShape)
                            .clickable { onClose() },
                ) {
                    Icon(
                        imageVector = Icons.Filled.Close,
                        contentDescription = "Close staged viewport",
                        tint = Color.White,
                        modifier = Modifier.size(16.dp),
                    )
                }
                Spacer(modifier = Modifier.weight(1f))
            }
        }

        Box(
            modifier =
                Modifier
                    .padding(top = 10.dp)
                    .size(stageSize.first, stageSize.second)
                    .shadow(18.dp, RoundedCornerShape(26.dp)),
        ) {
            Box(
                modifier =
                    Modifier
                        .fillMaxSize()
                        .clip(RoundedCornerShape(26.dp))
                        .border(1.dp, MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.7f), RoundedCornerShape(26.dp)),
            ) {
                content()
            }
        }
    }
}
