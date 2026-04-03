package com.mollotov.browser.ui

import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.ArrowForward
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.unit.dp

@Composable
fun URLBar(
    currentUrl: String,
    canGoBack: Boolean,
    canGoForward: Boolean,
    onNavigate: (String) -> Unit,
    onBack: () -> Unit,
    onForward: () -> Unit,
    onAI: () -> Unit,
    onSnapshot3D: () -> Unit,
    modifier: Modifier = Modifier,
) {
    var urlText by remember(currentUrl) { mutableStateOf(currentUrl) }
    val navigationButtonSize = 44.dp

    Row(
        verticalAlignment = Alignment.CenterVertically,
        modifier = modifier
            .fillMaxWidth()
            .padding(horizontal = 8.dp, vertical = 4.dp),
    ) {
        IconButton(onClick = onBack, enabled = canGoBack, modifier = Modifier.size(navigationButtonSize)) {
            Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
        }
        IconButton(onClick = onForward, enabled = canGoForward, modifier = Modifier.size(navigationButtonSize)) {
            Icon(Icons.AutoMirrored.Filled.ArrowForward, contentDescription = "Forward")
        }

        OutlinedTextField(
            value = urlText,
            onValueChange = { urlText = it },
            singleLine = true,
            placeholder = { Text("Enter URL") },
            shape = CircleShape,
            keyboardOptions = KeyboardOptions(imeAction = ImeAction.Go),
            keyboardActions = KeyboardActions(onGo = {
                val url = if (urlText.startsWith("http://") || urlText.startsWith("https://")) {
                    urlText
                } else {
                    "https://$urlText"
                }
                onNavigate(url)
            }),
            modifier = Modifier
                .weight(1f)
                .padding(horizontal = 4.dp),
        )

        IconButton(onClick = onAI, modifier = Modifier.size(navigationButtonSize)) {
            Text("AI")
        }

        IconButton(onClick = onSnapshot3D, modifier = Modifier.size(navigationButtonSize)) {
            Text("3D")
        }
    }
}
