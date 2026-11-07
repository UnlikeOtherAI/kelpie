package com.kelpie.browser.ai

import android.content.Context
import android.os.Build
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

class PlatformAIEngine(
    private val context: Context,
) {
    companion object {
        @Suppress("UNUSED_PARAMETER")
        fun isAvailable(context: Context): Boolean {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                return false
            }
            return try {
                Class.forName("com.google.ai.edge.aicore.GenerativeModel")
                true
            } catch (_: ClassNotFoundException) {
                false
            } catch (_: Exception) {
                false
            }
        }
    }

    suspend fun infer(prompt: String): String =
        withContext(Dispatchers.IO) {
            if (!isAvailable(context)) {
                throw IllegalStateException("Platform AI is unavailable on this device")
            }
            if (prompt.isBlank()) {
                throw IllegalArgumentException("Prompt must not be blank")
            }
            try {
                inferViaAICore(prompt)
            } catch (e: ClassNotFoundException) {
                throw UnsupportedOperationException("AI Edge SDK not available at runtime: ${e.message}")
            }
        }

    private suspend fun inferViaAICore(prompt: String): String {
        // The AI Edge SDK's generateContent() is a Kotlin suspend function.
        // Suspend functions cannot be called via Java reflection because the compiler
        // appends a Continuation parameter to the JVM method signature.
        // This reflection path is a best-effort placeholder — it will be replaced with
        // direct SDK calls when the dependency is uncommented in build.gradle.kts.
        // For now, isAvailable() returns false when the SDK isn't on the classpath,
        // so this code path is unreachable in practice.
        val modelClass = Class.forName("com.google.ai.edge.aicore.GenerativeModel")

        // Try to find a blocking/Java-friendly API first (some SDK versions expose one)
        val generateMethod =
            try {
                modelClass.getMethod("generateContentBlocking", Class.forName("com.google.ai.edge.aicore.Content"))
            } catch (_: NoSuchMethodException) {
                throw UnsupportedOperationException(
                    "AI Edge SDK is present but does not expose a blocking API. " +
                        "Enable the compile dependency in build.gradle.kts for proper suspend function support.",
                )
            }

        val contentBuilderClass = Class.forName("com.google.ai.edge.aicore.Content\$Builder")

        @Suppress("DEPRECATION")
        val builder = contentBuilderClass.newInstance()
        val addTextMethod = contentBuilderClass.getMethod("addText", String::class.java)
        addTextMethod.invoke(builder, prompt)
        val buildMethod = contentBuilderClass.getMethod("build")
        val content = buildMethod.invoke(builder)

        val constructor = modelClass.getConstructor(String::class.java)

        @Suppress("DEPRECATION")
        val model = constructor.newInstance("gemini-nano")

        val response = generateMethod.invoke(model, content)
        val getTextMethod = response!!.javaClass.getMethod("getText")
        return getTextMethod.invoke(response) as? String ?: ""
    }
}
