package com.kelpie.browser.browser

import org.json.JSONObject

internal data class DocumentResponse(
    val url: String,
    val status: Int,
    val mimeType: String?,
)

class BrowserDiagnostics {
    private val console = ArrayDeque<Map<String, Any?>>()
    private val network = ArrayDeque<Map<String, Any?>>()

    internal var documentResponse: DocumentResponse? = null

    @Synchronized
    fun recordConsole(message: Map<String, Any?>) {
        console.addLast(message)
        if (console.size > 5000) console.removeFirst()
    }

    @Synchronized
    fun snapshotConsole(): List<Map<String, Any?>> = console.toList()

    @Synchronized
    fun clearConsole(): Int = console.size.also { console.clear() }

    @Synchronized
    fun recordNetwork(event: JSONObject) {
        network.addLast(
            mapOf(
                "type" to event.optString("type"),
                "url" to event.optString("url"),
                "started" to event.optDouble("started"),
                "statusCode" to event.optInt("statusCode"),
                "statusText" to event.optString("statusText"),
                "method" to event.optString("method"),
                "mimeType" to event.optString("contentType"),
                "duration" to event.optInt("duration"),
                "failure" to if (event.isNull("failure")) null else event.optString("failure"),
            ),
        )
        if (network.size > 2000) network.removeFirst()
    }

    @Synchronized
    fun snapshotNetwork(): List<Map<String, Any?>> = network.toList()
}
