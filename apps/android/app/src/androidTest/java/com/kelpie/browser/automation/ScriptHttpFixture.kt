package com.kelpie.browser.automation

import androidx.test.platform.app.InstrumentationRegistry
import com.kelpie.browser.BuildConfig
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import java.net.HttpURLConnection
import java.net.URL
import java.util.UUID

/** Public HTTP/MCP client. Bearer material stays in memory and is never asserted/logged. */
class ScriptHttpFixture : AutoCloseable {
    private val base = "http://127.0.0.1:" + BuildConfig.LOCAL_HTTP_PORT
    private var token: String? = null

    fun request(
        path: String,
        value: JSONObject? = null,
        authenticated: Boolean = true,
        method: String = if (value == null) "GET" else "POST",
    ): Pair<Int, JSONObject> {
        val connection = URL(base + path).openConnection() as HttpURLConnection
        try {
            connection.connectTimeout = 5_000
            connection.readTimeout = 60_000
            connection.requestMethod = method
            connection.setRequestProperty("Content-Type", "application/json")
            if (authenticated) token?.let { connection.setRequestProperty("Authorization", "Bearer " + it) }
            if (value != null) {
                connection.doOutput = true
                connection.outputStream.use { it.write(value.toString().toByteArray(Charsets.UTF_8)) }
            }
            val status = connection.responseCode
            val stream = if (status < 400) connection.inputStream else connection.errorStream
            val body = stream?.bufferedReader()?.use { it.readText() }.orEmpty()
            if (path == "/v1/play-script") {
                // Authored fixture replies only: never pairing responses or credentials.
                val context =
                    androidx.test.platform.app.InstrumentationRegistry
                        .getInstrumentation()
                        .targetContext
                val folder = java.io.File(context.getExternalFilesDir(null), "script-acceptance").apply { mkdirs() }
                java.io.File(folder, "script-reply-" + UUID.randomUUID() + "-http-" + status + ".json").writeText(body)
            }
            return status to if (body.isEmpty()) JSONObject() else JSONObject(body)
        } finally {
            connection.disconnect()
        }
    }

    fun waitForListener() {
        val deadline = System.nanoTime() + 10_000_000_000L
        while (true) {
            try {
                request("/health", authenticated = false)
                return
            } catch (error: java.io.IOException) {
                if (System.nanoTime() >= deadline) throw error
                Thread.sleep(50)
            }
        }
    }

    fun beginPair(): String {
        val response =
            request(
                "/v1/pair",
                JSONObject().put("clientId", UUID.randomUUID().toString()).put("clientName", "Script native verification"),
                authenticated = false,
            )
        assertTrue(response.first in 200..299)
        return response.second.getString("requestId")
    }

    fun finishPair(id: String) {
        val response = request("/v1/pair/status?requestId=" + id, authenticated = false)
        assertEquals(200, response.first)
        token = response.second.getString("token")
        assertTrue(!token.isNullOrEmpty())
    }

    fun call(
        method: String,
        body: JSONObject = JSONObject(),
    ): JSONObject {
        val response = request("/v1/" + method, body)
        assertEquals("HTTP status for " + method + " code=" + response.second.optJSONObject("error")?.optString("code"), 200, response.first)
        return response.second
    }

    fun mcp(
        name: String,
        arguments: JSONObject = JSONObject(),
    ): JSONObject {
        val response =
            request(
                "/mcp",
                JSONObject()
                    .put("jsonrpc", "2.0")
                    .put("id", 1)
                    .put("method", "tools/call")
                    .put("params", JSONObject().put("name", name).put("arguments", arguments)),
            )
        assertEquals(200, response.first)
        val content = response.second.getJSONObject("result").getJSONArray("content")
        val text = (0 until content.length()).map(content::getJSONObject).first { it.optString("type") == "text" }.getString("text")
        return JSONObject(text)
    }

    fun mcpValue(
        name: String,
        arguments: JSONObject = JSONObject(),
    ): JSONObject {
        val envelope = mcp(name, arguments)
        assertTrue("Native MCP tool refused " + name, envelope.getBoolean("ok"))
        return envelope.getJSONObject("value")
    }

    fun core(
        method: String,
        tab: String,
        params: JSONObject = JSONObject(),
    ): JSONObject {
        val response =
            call(
                "browser-control",
                JSONObject()
                    .put("version", 1)
                    .put("method", method)
                    .put("tabId", tab)
                    .put("params", params),
            )
        if (!response.getBoolean("ok") && method == "tab.ready") recordApi29ReadyRefusal(response)
        assertTrue("Canonical " + method + " refused", response.getBoolean("ok"))
        return response
    }

    private fun recordApi29ReadyRefusal(response: JSONObject) {
        val args = InstrumentationRegistry.getArguments()
        if (args.getString("api29Smoke") != "true") return
        val caseName =
            when (args.getString("api29Case")) {
                "one-step-png" -> "one-step-png"
                "movie-stop" -> "movie-stop"
                else -> return
            }
        val error = response.optJSONObject("error")
        val code =
            when (error?.optString("code")) {
                "COMMAND_FAILED" -> "COMMAND_FAILED"
                "ACCESS_DENIED" -> "ACCESS_DENIED"
                "INVALID_ARGUMENTS" -> "INVALID_ARGUMENTS"
                "UNSUPPORTED" -> "UNSUPPORTED"
                "TAB_REQUIRED" -> "TAB_REQUIRED"
                "BUSY" -> "BUSY"
                else -> "OTHER"
            }
        val receipt =
            JSONObject()
                .put("stage", "PUBLIC_TAB_READY")
                .put("code", code)
                .put("errorObject", error != null)
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val folder = java.io.File(context.getExternalFilesDir(null), "script-acceptance").apply { mkdirs() }
        java.io.File(folder, "api29-ready-refusal-$caseName.json").writeText(receipt.toString(2))
    }

    fun script(
        tab: String,
        vararg actions: JSONObject,
    ): JSONObject = JSONObject().put("version", 1).put("tabId", tab).put("actions", JSONArray(actions.toList()))

    fun action(name: String): JSONObject = JSONObject().put("action", name)

    fun target(name: String): JSONObject = JSONObject().put("role", "button").put("name", name).put("exact", true)

    override fun close() {
        if (token != null) {
            try {
                request("/v1/pair", method = "DELETE")
            } finally {
                token = null
            }
        }
    }
}
