package com.kelpie.browser.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Popup
import androidx.compose.ui.window.PopupProperties

@Composable
fun RecordingStopButton(
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Box(
        contentAlignment = Alignment.Center,
        modifier =
            modifier
                .size(40.dp)
                .background(Color(0xB8D63C3C), CircleShape)
                .semantics { contentDescription = "Stop recording" }
                .clickable(onClick = onClick),
    ) {
        Text(
            text = "■",
            color = Color.White,
            fontWeight = FontWeight.Bold,
        )
    }
}

@Composable
internal fun RecordingStopPopup(onStop: () -> Unit) {
    Popup(alignment = Alignment.TopEnd, properties = PopupProperties(focusable = false)) {
        Box(Modifier.statusBarsPadding().padding(top = 12.dp, end = 12.dp)) {
            RecordingStopButton(onClick = onStop)
        }
    }
}
