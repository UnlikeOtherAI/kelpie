package com.kelpie.browser.ui

import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Column
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.platform.LocalContext
import com.kelpie.browser.ai.LocalInference
import kotlinx.coroutines.launch
import java.io.File

@Composable
internal fun LocalModelSection() {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val prefs = remember { context.getSharedPreferences("local-model", 0) }
    var path by remember { mutableStateOf(prefs.getString("path", null)) }
    var busy by remember { mutableStateOf(false) }
    var message by remember { mutableStateOf("Import a small instruction GGUF for offline text inference. Use a LAN endpoint below for larger models.") }
    fun load(selected: String) {
        busy = true
        message = "Loading on this device…"
        scope.launch {
            try {
                val result = LocalInference.load(context, mapOf("model" to selected))
                if (result["success"] == true) {
                    path = selected
                    prefs.edit().putString("path", selected).apply()
                    message = "On-device model ready"
                } else {
                    message = (result["error"] as? Map<*, *>)?.get("message") as? String ?: "Could not load model"
                }
            } finally {
                busy = false
            }
        }
    }
    val importer = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
        if (uri != null) {
            busy = true
            message = "Importing model…"
            scope.launch {
                try {
                    val selected = LocalInference.importModel(context, uri)
                    path = selected
                    prefs.edit().putString("path", selected).apply()
                    load(selected)
                } catch (error: Exception) {
                    message = error.message ?: "Could not import model"
                    busy = false
                }
            }
        }
    }
    Column {
        Text("On-device model")
        Text(message)
        TextButton(enabled = !busy, onClick = { importer.launch(arrayOf("*/*")) }) { Text("Import GGUF model") }
        path?.takeIf { File(it).isFile }?.let { selected ->
            TextButton(enabled = !busy, onClick = { load(selected) }) { Text("Use imported model") }
        }
        if (busy) TextButton(onClick = { LocalInference.cancel() }) { Text("Cancel") }
    }
}
