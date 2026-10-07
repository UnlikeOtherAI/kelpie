package com.kelpie.browser.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import com.kelpie.browser.ai.openai.HealthState
import com.kelpie.browser.ai.openai.OpenAIEndpoint
import com.kelpie.browser.ai.openai.OpenAIException
import com.kelpie.browser.ai.openai.OpenAIRuntime
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

private sealed class EditorTarget {
    data object New : EditorTarget()

    data class Existing(
        val endpoint: OpenAIEndpoint,
    ) : EditorTarget()
}

/** OpenAI-compatible endpoint list inside the AI sheet: health, Refresh models, Test, Use, Edit, Remove. */
@Composable
internal fun OpenAIEndpointsSection() {
    if (!OpenAIRuntime.isInitialized) return
    val service = OpenAIRuntime.service
    val revision by service.revision.collectAsState()
    val scope = rememberCoroutineScope()
    var now by remember { mutableLongStateOf(System.currentTimeMillis()) }
    var editor by remember { mutableStateOf<EditorTarget?>(null) }
    var confirmRemove by remember { mutableStateOf<OpenAIEndpoint?>(null) }
    var message by remember { mutableStateOf<String?>(null) }
    var busy by remember { mutableStateOf<String?>(null) }
    val endpoints = remember(revision) { service.store.all() }
    val activeId = remember(revision) { if (service.isOpenAIActive) service.store.active()?.endpointId else null }
    val nowMs = remember(revision, now) { System.currentTimeMillis() }

    LaunchedEffect(Unit) {
        while (true) {
            delay(15_000)
            now = System.currentTimeMillis()
        }
    }

    fun run(
        label: String,
        block: suspend () -> String,
    ) = scope.runAction(label, onBusy = { busy = it }, onMessage = { message = it }, block = block)

    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Text("OpenAI-compatible endpoints", style = MaterialTheme.typography.titleMedium)
        Text(OPENAI_LOOPBACK_HELP, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        if (endpoints.isEmpty()) {
            Text("No endpoints saved.", style = MaterialTheme.typography.bodyMedium)
        }
        endpoints.forEach { endpoint ->
            HorizontalDivider()
            EndpointRow(
                endpoint = endpoint,
                state = service.healthOf(endpoint.id).effectiveState(nowMs, service.inFlightCount(endpoint.id)),
                isActive = endpoint.id == activeId,
                busy = busy != null,
                onRefresh = {
                    run("Refresh models") {
                        val result = service.discover(endpoint.id)
                        result.warning ?: "Found ${result.models.size} model(s) on ${endpoint.name}"
                    }
                },
                onTest = {
                    run("Test") {
                        val result = OpenAIRuntime.tester.test(endpoint.id, null, generate = true, tools = true)
                        describeTest(result)
                    }
                },
                onUse = {
                    run("Use") {
                        service.activate(endpoint.id, null)
                        OpenAIRuntime.monitor.refresh()
                        "${endpoint.name} is now the active AI backend"
                    }
                },
                onEdit = { editor = EditorTarget.Existing(endpoint) },
                onRemove = { confirmRemove = endpoint },
            )
        }
        busy?.let { Text("$it…", style = MaterialTheme.typography.bodySmall) }
        message?.let { Text(it, style = MaterialTheme.typography.bodySmall) }
        TextButton(onClick = { editor = EditorTarget.New }) { Text("Add endpoint") }
    }

    editor?.let { target ->
        val existing = (target as? EditorTarget.Existing)?.endpoint
        OpenAIEndpointEditor(
            endpoint = existing,
            hasSavedKey = existing?.let { service.store.hasApiKey(it.id) } ?: false,
            onSave = { input ->
                val saved = service.save(input)
                OpenAIRuntime.monitor.refresh()
                message = "Saved ${saved.name}. Use Test or Refresh models to connect."
                editor = null
            },
            onDismiss = { editor = null },
        )
    }

    confirmRemove?.let { endpoint ->
        AlertDialog(
            onDismissRequest = { confirmRemove = null },
            title = { Text("Remove ${endpoint.name}?") },
            text = { Text("Its saved API key is deleted too. If it is the active backend, AI is unloaded.") },
            confirmButton = {
                TextButton(onClick = {
                    service.remove(endpoint.id)
                    OpenAIRuntime.monitor.refresh()
                    confirmRemove = null
                }) { Text("Remove") }
            },
            dismissButton = { TextButton(onClick = { confirmRemove = null }) { Text("Cancel") } },
        )
    }
}

@Composable
private fun EndpointRow(
    endpoint: OpenAIEndpoint,
    state: HealthState,
    isActive: Boolean,
    busy: Boolean,
    onRefresh: () -> Unit,
    onTest: () -> Unit,
    onUse: () -> Unit,
    onEdit: () -> Unit,
    onRemove: () -> Unit,
) {
    Column(modifier = Modifier.fillMaxWidth().padding(vertical = 4.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(endpoint.name, style = MaterialTheme.typography.bodyLarge)
            if (isActive) Text("  • In use", style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.primary)
            Spacer(Modifier.weight(1f))
            HealthBadge(state)
        }
        Text(endpoint.baseURL, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        if (endpoint.loopback) {
            Text("localhost = this phone", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.tertiary)
        }
        Text("Model: ${endpoint.model ?: "none selected"}", style = MaterialTheme.typography.bodySmall)
        Row {
            TextButton(onClick = onRefresh, enabled = !busy) { Text("Refresh models") }
            TextButton(onClick = onTest, enabled = !busy) { Text("Test") }
            TextButton(onClick = onUse, enabled = !busy && !isActive) { Text("Use") }
        }
        Row {
            TextButton(onClick = onEdit, enabled = !busy) { Text("Edit") }
            TextButton(onClick = onRemove, enabled = !busy) { Text("Remove") }
        }
    }
}

@Composable
private fun HealthBadge(state: HealthState) {
    val color =
        when (state) {
            HealthState.READY -> Color(0xFF2E7D32)
            HealthState.BUSY -> Color(0xFF1565C0)
            HealthState.LOADING, HealthState.NO_MODEL, HealthState.MODEL_MISSING -> Color(0xFFF9A825)
            HealthState.UNREACHABLE, HealthState.AUTH_FAILED -> Color(0xFFC62828)
            HealthState.UNKNOWN -> Color(0xFF9E9E9E)
        }
    Row(verticalAlignment = Alignment.CenterVertically) {
        Box(Modifier.size(8.dp).background(color, CircleShape))
        Text(" ${state.wire.replace('_', ' ')}", style = MaterialTheme.typography.labelMedium)
    }
}

private fun CoroutineScope.runAction(
    label: String,
    onBusy: (String?) -> Unit,
    onMessage: (String) -> Unit,
    block: suspend () -> String,
) {
    launch {
        onBusy(label)
        val text =
            try {
                withContext(Dispatchers.IO) { block() }
            } catch (e: OpenAIException) {
                "$label failed: ${e.message}"
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                "$label failed: ${e.message ?: e.javaClass.simpleName}"
            }
        onBusy(null)
        onMessage(text)
    }
}

private fun describeTest(result: Map<String, Any?>): String {
    val health = (result["health"] as? Map<*, *>)?.get("state") ?: "unknown"
    val generation = (result["generation"] as? Map<*, *>)?.get("ok")
    val tools = (result["toolCalling"] as? Map<*, *>)?.get("ok")
    return "Health: $health · generation: ${okText(generation)} · tool calling: ${okText(tools)}"
}

private fun okText(value: Any?): String =
    when (value) {
        true -> "ok"
        false -> "failed"
        else -> "not run"
    }
