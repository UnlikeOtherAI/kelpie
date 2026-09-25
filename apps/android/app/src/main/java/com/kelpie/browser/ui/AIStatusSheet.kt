package com.kelpie.browser.ui

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp

@Composable
internal fun AIStatusSheet(onDismiss: () -> Unit) {
    Column(
        modifier =
            Modifier
                .fillMaxWidth()
                .padding(horizontal = 24.dp, vertical = 16.dp),
    ) {
        Text("Local AI", style = MaterialTheme.typography.headlineSmall)
        Spacer(Modifier.size(12.dp))
        AIInfoRow("Backend", if (com.kelpie.browser.ai.AIState.backend == com.kelpie.browser.ai.AIState.OLLAMA_BACKEND) "Ollama" else "Platform")
        AIInfoRow("Availability", if (com.kelpie.browser.ai.AIState.isAvailable) "Available" else "Unavailable")
        AIInfoRow("Active Model", com.kelpie.browser.ai.AIState.activeModel ?: if (com.kelpie.browser.ai.AIState.isAvailable) "Platform AI" else "None")
        AIInfoRow(
            "Capabilities",
            if (com.kelpie.browser.ai.AIState.isAvailable || com.kelpie.browser.ai.AIState.activeModel != null) "text" else "None",
        )
        com.kelpie.browser.ai.AIState.ollamaEndpoint?.let { endpoint ->
            AIInfoRow("Ollama", endpoint)
        }
        Spacer(Modifier.size(12.dp))
        Text(
            text =
                if (com.kelpie.browser.ai.AIState.isAvailable) {
                    "AI is available from the browser shell and the HTTP API."
                } else {
                    "Platform AI is unavailable on this device right now. You can still load an Ollama model over the API."
                },
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        Spacer(Modifier.size(16.dp))
        TextButton(onClick = onDismiss, modifier = Modifier.align(Alignment.End)) {
            Text("Done")
        }
    }
}

@Composable
private fun AIInfoRow(
    label: String,
    value: String,
) {
    Row(modifier = Modifier.fillMaxWidth()) {
        Text(label, color = MaterialTheme.colorScheme.onSurfaceVariant)
        Spacer(Modifier.weight(1f))
        Text(value)
    }
}
