package com.kelpie.browser.ui

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.kelpie.browser.ai.AIState
import com.kelpie.browser.ai.openai.OpenAIRuntime
import kotlinx.coroutines.flow.MutableStateFlow
import java.io.File

@Composable
internal fun AIStatusSheet(onDismiss: () -> Unit) {
    // Health polling runs while the sheet is open (and while the openai backend is active).
    DisposableEffect(Unit) {
        if (OpenAIRuntime.isInitialized) OpenAIRuntime.monitor.setSheetOpen(true)
        onDispose { if (OpenAIRuntime.isInitialized) OpenAIRuntime.monitor.setSheetOpen(false) }
    }
    val revisionFlow = remember { if (OpenAIRuntime.isInitialized) OpenAIRuntime.service.revision else MutableStateFlow(0L) }
    val revision by revisionFlow.collectAsState()
    val openAIEndpoint = if (revision >= 0 && AIState.backend == AIState.OPENAI_BACKEND) OpenAIRuntime.service.activeEndpoint() else null
    val ready = if (openAIEndpoint != null) OpenAIRuntime.service.healthPublic(openAIEndpoint.id)["state"] == "ready"
        else if (AIState.backend == AIState.PLATFORM_BACKEND) AIState.isAvailable else AIState.activeModel != null

    Column(
        modifier =
            Modifier
                .fillMaxWidth()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 24.dp, vertical = 16.dp),
    ) {
        Text("Local AI", style = MaterialTheme.typography.headlineSmall)
        Spacer(Modifier.size(12.dp))
        AIInfoRow("Backend", backendLabel(AIState.backend))
        AIInfoRow("Availability", if (ready) "Available" else "Unavailable")
        val activeModel =
            openAIEndpoint?.let {
                OpenAIRuntime.service.store
                    .active()
                    ?.model ?: it.model
            }
                ?: AIState.activeModel?.let { if (AIState.backend == "native") File(it).name else it }
                ?: if (AIState.isAvailable) "Platform AI" else "None"
        AIInfoRow("Active Model", activeModel)
        AIInfoRow(
            "Capabilities",
            if (AIState.isAvailable || AIState.activeModel != null || openAIEndpoint != null) "text" else "None",
        )
        AIState.ollamaEndpoint?.let { endpoint ->
            AIInfoRow("Ollama", endpoint)
        }
        openAIEndpoint?.let { AIInfoRow("Endpoint", it.name) }
        Spacer(Modifier.size(12.dp))
        Text(
            text =
                if (ready) {
                    "AI is available from the browser shell and the HTTP API."
                } else {
                    "Import a GGUF for on-device inference, or select a reachable LAN endpoint for a larger model."
                },
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        Spacer(Modifier.size(16.dp))
        LocalModelSection()
        Spacer(Modifier.size(16.dp))
        OpenAIEndpointsSection()
        Spacer(Modifier.size(16.dp))
        TextButton(onClick = onDismiss, modifier = Modifier.align(Alignment.End)) {
            Text("Done")
        }
    }
}

private fun backendLabel(backend: String): String =
    when (backend) {
        AIState.OLLAMA_BACKEND -> "Ollama"
        AIState.OPENAI_BACKEND -> "OpenAI-compatible"
        "native" -> "On-device GGUF"
        else -> "Platform"
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
