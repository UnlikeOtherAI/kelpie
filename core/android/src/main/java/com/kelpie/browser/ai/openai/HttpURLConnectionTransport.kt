package com.kelpie.browser.ai.openai

import kotlinx.coroutines.TimeoutCancellationException
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withTimeout
import java.io.ByteArrayOutputStream
import java.io.IOException
import java.io.InputStream
import java.net.HttpURLConnection
import java.net.SocketTimeoutException
import java.net.URL
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicReference

/**
 * [OpenAITransport] over `HttpURLConnection`. Redirects are followed manually and only
 * within the same origin.
 *
 * The blocking exchange runs on a worker thread outside structured concurrency so that
 * cancelling the caller (or hitting the overall deadline) returns immediately: the
 * connection is disconnected, the worker is told to stop delivering bytes, and its late
 * result is discarded. (Some `HttpURLConnection` implementations drain a keep-alive body
 * on disconnect instead of aborting the blocked read, so the caller never waits on it.)
 */
class HttpURLConnectionTransport(
    private val openConnection: (URL) -> HttpURLConnection = { it.openConnection() as HttpURLConnection },
) : OpenAITransport {
    override suspend fun execute(
        request: TransportRequest,
        onBody: (ByteArray, Int) -> Unit,
    ): TransportResponse {
        val exchange = Exchange(request, onBody)
        return try {
            withTimeout(request.timeouts.totalMs) { exchange.await() }
        } catch (e: TimeoutCancellationException) {
            throw timeout()
        }
    }

    /** One request/response on a worker thread, abortable from the calling coroutine. */
    private inner class Exchange(
        private val request: TransportRequest,
        private val onBody: (ByteArray, Int) -> Unit,
    ) {
        private val active = AtomicReference<HttpURLConnection?>()
        private val aborted = AtomicBoolean(false)

        suspend fun await(): TransportResponse =
            suspendCancellableCoroutine { continuation ->
                continuation.invokeOnCancellation { abort() }
                WORKERS.execute {
                    val result = runCatching { performWithRedirects() }
                    if (!aborted.get()) continuation.resumeWith(result)
                }
            }

        /** Runs from the cancelling thread, so the (possibly blocking) disconnect is handed to a worker. */
        private fun abort() {
            aborted.set(true)
            val connection = active.get() ?: return
            WORKERS.execute { runCatching { connection.disconnect() } }
        }

        private fun performWithRedirects(): TransportResponse {
            var url = request.url
            repeat(RedirectPolicy.MAX_REDIRECTS + 1) {
                val connection = open(url, request)
                active.set(connection)
                if (aborted.get()) throw IOException("aborted")
                try {
                    val status = connectAndSend(connection, request)
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
                    return readResponse(connection, status)
                } finally {
                    if (!aborted.get()) connection.disconnect()
                }
            }
            throw OpenAIException(OpenAIErrorCode.ENDPOINT_ERROR, "Too many redirects")
        }

        private fun readResponse(
            connection: HttpURLConnection,
            status: Int,
        ): TransportResponse {
            val contentType = connection.contentType
            if (status !in 200..299) {
                val text = guardRead { connection.errorStream?.let(::readBounded) }
                return TransportResponse(status, contentType, text ?: "")
            }
            guardRead {
                val stream = connection.inputStream
                val buffer = ByteArray(BUFFER_SIZE)
                while (!aborted.get()) {
                    val read = stream.read(buffer)
                    if (read < 0) break
                    if (read > 0 && !aborted.get()) onBody(buffer, read)
                }
                stream.close()
            }
            return TransportResponse(status, contentType, null)
        }
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
    ): Int {
        try {
            connection.connect()
        } catch (e: IOException) {
            throw unreachable(e)
        }
        return guardRead {
            request.body?.let { body -> connection.outputStream.use { it.write(body) } }
            connection.responseCode
        }
    }

    private inline fun <T> guardRead(block: () -> T): T =
        try {
            block()
        } catch (e: OpenAIException) {
            throw e
        } catch (e: SocketTimeoutException) {
            throw timeout()
        } catch (e: IOException) {
            throw OpenAIException(OpenAIErrorCode.ENDPOINT_UNREACHABLE, "Lost connection to the endpoint: ${e.message ?: e.javaClass.simpleName}")
        }

    private fun readBounded(stream: InputStream): String {
        val out = ByteArrayOutputStream()
        val buffer = ByteArray(BUFFER_SIZE)
        stream.use {
            while (out.size() < MAX_ERROR_BYTES) {
                val read = it.read(buffer, 0, minOf(buffer.size, MAX_ERROR_BYTES - out.size()))
                if (read < 0) break
                out.write(buffer, 0, read)
            }
        }
        return out.toString(Charsets.UTF_8.name())
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

        /** Daemon worker threads for blocking HTTP exchanges. */
        val WORKERS: ExecutorService =
            Executors.newCachedThreadPool { runnable ->
                Thread(runnable, "kelpie-openai-http").apply { isDaemon = true }
            }
    }
}
