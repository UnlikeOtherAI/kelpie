package com.kelpie.browser.ai.openai

import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import java.io.IOException
import java.io.InputStream
import java.net.HttpURLConnection
import java.net.SocketTimeoutException
import java.net.URL
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicReference

/**
 * [OpenAITransport] over `HttpURLConnection`. Redirects are followed manually and only
 * within the same origin. Cancelling the calling coroutine, or exceeding the overall
 * deadline, disconnects the socket so blocking reads end immediately.
 */
class HttpURLConnectionTransport(
    private val openConnection: (URL) -> HttpURLConnection = { it.openConnection() as HttpURLConnection },
) : OpenAITransport {
    override suspend fun execute(
        request: TransportRequest,
        onBody: (ByteArray, Int) -> Unit,
    ): TransportResponse =
        coroutineScope {
            val active = AtomicReference<HttpURLConnection?>()
            val deadlineHit = AtomicBoolean(false)
            val work = async(Dispatchers.IO) { performWithRedirects(request, onBody, active, deadlineHit) }
            val deadline =
                launch {
                    delay(request.timeouts.totalMs)
                    deadlineHit.set(true)
                    active.get()?.disconnect()
                }
            try {
                work.await()
            } catch (e: CancellationException) {
                active.get()?.disconnect()
                throw e
            } finally {
                deadline.cancel()
            }
        }

    private fun performWithRedirects(
        request: TransportRequest,
        onBody: (ByteArray, Int) -> Unit,
        active: AtomicReference<HttpURLConnection?>,
        deadlineHit: AtomicBoolean,
    ): TransportResponse {
        var url = request.url
        repeat(RedirectPolicy.MAX_REDIRECTS + 1) {
            val connection = open(url, request)
            active.set(connection)
            try {
                val status = connectAndSend(connection, request, deadlineHit)
                val location = connection.getHeaderField("Location")
                if (status in 300..399 && location != null) {
                    url = RedirectPolicy.resolveSameOrigin(url, location)
                        ?: throw OpenAIException(
                            OpenAIErrorCode.ENDPOINT_REDIRECT_REFUSED,
                            "The server redirected to a different origin; Kelpie only follows same-origin redirects",
                            httpStatus = status,
                        )
                    return@repeat
                }
                return readResponse(connection, status, onBody, deadlineHit)
            } finally {
                connection.disconnect()
            }
        }
        throw OpenAIException(OpenAIErrorCode.ENDPOINT_ERROR, "Too many redirects")
    }

    private fun open(
        url: String,
        request: TransportRequest,
    ): HttpURLConnection =
        try {
            openConnection(URL(url)).apply {
                instanceFollowRedirects = false
                requestMethod = request.method
                connectTimeout = request.timeouts.connectMs
                readTimeout = request.timeouts.readMs
                useCaches = false
                doInput = true
                doOutput = request.body != null
                request.headers.forEach { (name, value) -> setRequestProperty(name, value) }
            }
        } catch (e: IOException) {
            throw unreachable(e)
        }

    /** Connects, writes the body and returns the status code. Connection failures are `ENDPOINT_UNREACHABLE`. */
    private fun connectAndSend(
        connection: HttpURLConnection,
        request: TransportRequest,
        deadlineHit: AtomicBoolean,
    ): Int {
        try {
            connection.connect()
        } catch (e: IOException) {
            if (deadlineHit.get()) throw timeout()
            throw unreachable(e)
        }
        return guardRead(deadlineHit) {
            request.body?.let { body -> connection.outputStream.use { it.write(body) } }
            connection.responseCode
        }
    }

    private fun readResponse(
        connection: HttpURLConnection,
        status: Int,
        onBody: (ByteArray, Int) -> Unit,
        deadlineHit: AtomicBoolean,
    ): TransportResponse {
        val contentType = connection.contentType
        if (status !in 200..299) {
            val text = guardRead(deadlineHit) { connection.errorStream?.let { readBounded(it) } }
            return TransportResponse(status, contentType, text ?: "")
        }
        guardRead(deadlineHit) {
            connection.inputStream.use { stream ->
                val buffer = ByteArray(BUFFER_SIZE)
                while (true) {
                    val read = stream.read(buffer)
                    if (read < 0) break
                    if (read > 0) onBody(buffer, read)
                }
            }
        }
        return TransportResponse(status, contentType, null)
    }

    private inline fun <T> guardRead(
        deadlineHit: AtomicBoolean,
        block: () -> T,
    ): T =
        try {
            block()
        } catch (e: OpenAIException) {
            throw e
        } catch (e: SocketTimeoutException) {
            throw timeout()
        } catch (e: IOException) {
            if (deadlineHit.get()) throw timeout()
            throw OpenAIException(OpenAIErrorCode.ENDPOINT_UNREACHABLE, "Lost connection to the endpoint: ${e.message ?: e.javaClass.simpleName}")
        }

    private fun readBounded(stream: InputStream): String =
        stream.use {
            val bytes = it.readNBytesCompat(MAX_ERROR_BYTES)
            String(bytes, Charsets.UTF_8)
        }

    private fun InputStream.readNBytesCompat(limit: Int): ByteArray {
        val out = java.io.ByteArrayOutputStream()
        val buffer = ByteArray(BUFFER_SIZE)
        while (out.size() < limit) {
            val read = read(buffer, 0, minOf(buffer.size, limit - out.size()))
            if (read < 0) break
            out.write(buffer, 0, read)
        }
        return out.toByteArray()
    }

    private fun unreachable(e: IOException) =
        OpenAIException(
            OpenAIErrorCode.ENDPOINT_UNREACHABLE,
            "Could not connect to the endpoint: ${e.message ?: e.javaClass.simpleName}",
        )

    private fun timeout() = OpenAIException(OpenAIErrorCode.ENDPOINT_TIMEOUT, "The endpoint did not respond in time")

    private companion object {
        const val BUFFER_SIZE = 8 * 1024
        const val MAX_ERROR_BYTES = 16 * 1024
    }
}
