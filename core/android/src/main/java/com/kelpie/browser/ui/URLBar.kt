package com.kelpie.browser.ui

import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.ArrowForward
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp

@Composable
fun URLBar(
    currentUrl: String,
    canGoBack: Boolean,
    canGoForward: Boolean,
    onNavigate: (String) -> Unit,
    onBack: () -> Unit,
    onForward: () -> Unit,
    showAI: Boolean,
    onAI: () -> Unit,
    onSnapshot3D: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val navigationButtonSize = 44.dp

    Row(
        verticalAlignment = Alignment.CenterVertically,
        modifier =
            modifier
                .fillMaxWidth()
                .padding(horizontal = 8.dp, vertical = 4.dp),
    ) {
        IconButton(onClick = onBack, enabled = canGoBack, modifier = Modifier.size(navigationButtonSize)) {
            Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
        }
        IconButton(onClick = onForward, enabled = canGoForward, modifier = Modifier.size(navigationButtonSize)) {
            Icon(Icons.AutoMirrored.Filled.ArrowForward, contentDescription = "Forward")
        }

        HistoryAutocompleteField(
            currentUrl = currentUrl,
            placeholder = "Enter URL",
            onNavigate = onNavigate,
            shape = CircleShape,
            modifier =
                Modifier
                    .weight(1f)
                    .padding(horizontal = 4.dp),
        )

        if (showAI) {
            IconButton(onClick = onAI, modifier = Modifier.size(navigationButtonSize)) {
                Text("AI")
            }
        }

        IconButton(onClick = onSnapshot3D, modifier = Modifier.size(navigationButtonSize)) {
            Text("3D")
        }
    }
}
