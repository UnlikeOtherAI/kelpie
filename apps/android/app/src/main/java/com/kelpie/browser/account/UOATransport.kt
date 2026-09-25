package com.kelpie.browser.account

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonObject
import java.net.HttpURLConnection
import java.net.URL

/** No cookies, redirect following, disk caching or logging of identity requests. */
class UOATransport {
    data class Response(
        val data: ByteArray,
        val version: String?,
    ) {
        fun json(): JsonObject = Json.parseToJsonElement(data.toString(Charsets.UTF_8)).jsonObject
    }

    class Failure(
        val status: Int,
    ) : Exception(
            when (status) {
                401 -> "Your session expired. Please log in again."
                403 -> "Access to favourites was not granted."
                409 -> "Favourites changed on another device. Please try again."
                else -> "Could not complete the request. Please try again."
            },
        )

    suspend fun request(
        path: String,
        method: String = "GET",
        token: String? = null,
        body: String? = null,
        version: String? = null,
    ): Response =
        withContext(Dispatchers.IO) {
            require(path.startsWith("/oauth/") && !path.contains("..") && !path.contains('?'))
            val connection = URL(ORIGIN + path).openConnection() as HttpURLConnection
            try {
                connection.requestMethod = method
                connection.instanceFollowRedirects = false
                connection.useCaches = false
                connection.connectTimeout = 30000
                connection.readTimeout = 30000
                connection.setRequestProperty("Content-Type", "application/json")
                if (token != null) connection.setRequestProperty("Authorization", "Bearer $token")
                if (version != null) connection.setRequestProperty("If-Match", version)
                if (body != null) {
                    connection.doOutput = true
                    connection.outputStream.use { it.write(body.toByteArray(Charsets.UTF_8)) }
                }
                if (connection.responseCode !in 200..299) throw Failure(connection.responseCode)
                val bytes =
                    connection.inputStream.use { stream ->
                        val output = java.io.ByteArrayOutputStream()
                        val buffer = ByteArray(8192)
                        while (true) {
                            val count = stream.read(buffer)
                            if (count < 0) break
                            require(output.size() + count <= 5 * 1024 * 1024)
                            output.write(buffer, 0, count)
                        }
                        output.toByteArray()
                    }
                require(bytes.size <= 5 * 1024 * 1024)
                Response(bytes, connection.getHeaderField("ETag"))
            } finally {
                connection.disconnect()
            }
        }

    companion object {
        const val ORIGIN = "https://authentication.unlikeotherai.com"
    }
}
