package com.kelpie.browser.ai

import android.app.ActivityManager
import android.content.Context
import android.net.Uri
import com.kelpie.browser.nativecore.NativeCore
import com.kelpie.browser.ai.openai.OpenAIRuntime
import com.kelpie.browser.network.errorResponse
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONObject
import java.io.File
import java.io.DataInputStream
import java.util.UUID

/** Embedded CPU inference; importing a model never contacts a server. */
object LocalInference {
    suspend fun execute(operation: String, body: Map<String, Any?> = emptyMap()): Map<String, Any?> =
        withContext(Dispatchers.IO) {
            AIHttpJson.parseJsonObject(NativeCore.localInference(operation, JSONObject(body).toString()))
        }

    fun cancel() = NativeCore.cancelLocalInference()

    suspend fun load(context: Context, body: Map<String, Any?>): Map<String, Any?> {
        val path = body["model"] as? String ?: return errorResponse("MISSING_PARAM", "model is required")
        val info = ActivityManager.MemoryInfo()
        (context.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager).getMemoryInfo(info)
        // Leave room for the WebView and OS as well as the GGUF evaluation buffers.
        if (File(path).length() * 3 / 2 + 256L * 1024 * 1024 > info.availMem) {
            return errorResponse("MODEL_MEMORY_LIMIT", "Use a smaller GGUF model or a LAN inference endpoint")
        }
        val result = execute("load", body)
        if (result["success"] == true) {
            OpenAIRuntime.service.clearSelection()
            OpenAIRuntime.monitor.refresh()
            AIState.backend = "native"
            AIState.activeModel = path
        }
        return result
    }

    suspend fun importModel(context: Context, uri: Uri): String =
        withContext(Dispatchers.IO) {
            val directory = File(context.filesDir, "local-models").apply { mkdirs() }
            val file = File(directory, "${UUID.randomUUID()}.gguf")
            try {
                context.contentResolver.openInputStream(uri)?.use { input ->
                    file.outputStream().use { output -> input.copyTo(output) }
                } ?: error("Could not open the selected model")
                DataInputStream(file.inputStream()).use {
                    val magic = ByteArray(4)
                    it.readFully(magic)
                    require(String(magic, Charsets.US_ASCII) == "GGUF") { "Select a GGUF model file" }
                }
                file.absolutePath
            } catch (error: Exception) {
                file.delete()
                throw error
            }
        }
}
