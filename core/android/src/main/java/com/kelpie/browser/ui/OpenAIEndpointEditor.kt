package com.kelpie.browser.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import com.kelpie.browser.ai.openai.EndpointSaveInput
import com.kelpie.browser.ai.openai.OpenAIEndpoint
import com.kelpie.browser.ai.openai.OpenAIException
import com.kelpie.browser.ai.openai.Patch

/** Add / edit form for one OpenAI-compatible endpoint. Saving validates but never connects. */
@Composable
internal fun OpenAIEndpointEditor(
    endpoint: OpenAIEndpoint?,
    hasSavedKey: Boolean,
    onSave: (EndpointSaveInput) -> Unit,
    onDismiss: () -> Unit,
) {
    var name by remember { mutableStateOf(endpoint?.name.orEmpty()) }
    var baseURL by remember { mutableStateOf(endpoint?.baseURL.orEmpty()) }
    var apiKey by remember { mutableStateOf("") }
    var clearKey by remember { mutableStateOf(false) }
    var model by remember { mutableStateOf(endpoint?.model.orEmpty()) }
    var contextWindow by remember {
        mutableStateOf(
            endpoint
                ?.user
                ?.contextWindow
                ?.toString()
                .orEmpty(),
        )
    }
    var vision by remember { mutableStateOf(endpoint?.user?.vision) }
    var toolCalling by remember { mutableStateOf(endpoint?.user?.toolCalling) }
    var error by remember { mutableStateOf<String?>(null) }

    fun submit() {
        val window = contextWindow.trim()
        if (window.isNotEmpty() && (window.toIntOrNull() ?: 0) <= 0) {
            error = "Context window must be a positive number"
            return
        }
        val input =
            EndpointSaveInput(
                id = endpoint?.id,
                name = name,
                baseURL = baseURL,
                apiKey = apiKey.takeIf { it.isNotBlank() && !clearKey },
                clearApiKey = clearKey,
                model = Patch(model.trim().ifEmpty { null }),
                contextWindow = Patch(window.toIntOrNull()),
                vision = Patch(vision),
                toolCalling = Patch(toolCalling),
            )
        try {
            onSave(input)
        } catch (e: OpenAIException) {
            error = e.message
        }
    }

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(if (endpoint == null) "Add endpoint" else "Edit endpoint") },
        text = {
            Column(
                modifier = Modifier.verticalScroll(rememberScrollState()),
                verticalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                OutlinedTextField(name, { name = it }, label = { Text("Name") }, singleLine = true, modifier = Modifier.fillMaxWidth())
                OutlinedTextField(
                    baseURL,
                    { baseURL = it },
                    label = { Text("Base URL") },
                    placeholder = { Text("http://192.168.1.20:8080/v1") },
                    singleLine = true,
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Uri),
                    modifier = Modifier.fillMaxWidth(),
                )
                Text(OPENAI_LOOPBACK_HELP, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                ApiKeyField(apiKey, { apiKey = it }, hasSavedKey && !clearKey, onClear = {
                    clearKey = true
                    apiKey = ""
                })
                ModelField(model, { model = it }, endpoint?.models?.map { it.id }.orEmpty())
                OutlinedTextField(
                    contextWindow,
                    { contextWindow = it.filter(Char::isDigit) },
                    label = { Text("Context window (tokens)") },
                    placeholder = { Text("Unknown") },
                    singleLine = true,
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
                    modifier = Modifier.fillMaxWidth(),
                )
                TriStateRow("Vision", vision) { vision = it }
                TriStateRow("Tool calling", toolCalling) { toolCalling = it }
                error?.let { Text(it, color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodySmall) }
            }
        },
        confirmButton = { TextButton(onClick = ::submit) { Text("Save") } },
        dismissButton = { TextButton(onClick = onDismiss) { Text("Cancel") } },
    )
}

@Composable
private fun ApiKeyField(
    value: String,
    onChange: (String) -> Unit,
    showSaved: Boolean,
    onClear: () -> Unit,
) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        OutlinedTextField(
            value,
            onChange,
            label = { Text("API key (optional)") },
            placeholder = { Text(if (showSaved) "Saved — type to replace" else "None") },
            singleLine = true,
            visualTransformation = PasswordVisualTransformation(),
            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password),
            modifier = Modifier.weight(1f),
        )
        if (showSaved) {
            TextButton(onClick = onClear) { Text("Clear") }
        }
    }
}

@Composable
private fun ModelField(
    value: String,
    onChange: (String) -> Unit,
    discovered: List<String>,
) {
    var expanded by remember { mutableStateOf(false) }
    Row(verticalAlignment = Alignment.CenterVertically) {
        OutlinedTextField(
            value,
            onChange,
            label = { Text("Model ID") },
            placeholder = { Text("Exactly as the server names it") },
            singleLine = true,
            modifier = Modifier.weight(1f),
        )
        if (discovered.isNotEmpty()) {
            Box {
                TextButton(onClick = { expanded = true }) { Text("Pick") }
                DropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
                    discovered.forEach { id ->
                        DropdownMenuItem(text = { Text(id) }, onClick = {
                            onChange(id)
                            expanded = false
                        })
                    }
                }
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun TriStateRow(
    label: String,
    value: Boolean?,
    onChange: (Boolean?) -> Unit,
) {
    Column {
        Text(label, style = MaterialTheme.typography.labelLarge)
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            listOf<Pair<String, Boolean?>>("Unknown" to null, "Yes" to true, "No" to false).forEach { (title, option) ->
                FilterChip(selected = value == option, onClick = { onChange(option) }, label = { Text(title) })
            }
        }
    }
}

internal const val OPENAI_LOOPBACK_HELP =
    "localhost means this phone. To use a server on your computer, enter its LAN or .local address " +
        "and make sure that server listens on the network."
