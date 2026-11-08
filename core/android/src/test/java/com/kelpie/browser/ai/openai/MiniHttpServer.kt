package com.kelpie.browser.ai.openai

import java.io.BufferedInputStream
import java.io.OutputStream
import java.net.InetAddress
import java.net.ServerSocket
import java.net.Socket
import kotlin.concurrent.thread

/** Minimal HTTP/1.1 test server on 127.0.0.1 (the JDK HttpServer is not on the Android unit-test classpath). */
class MiniHttpServer(
    private val handler: (Request, OutputStream) -> Unit,
) : AutoCloseable {
    class Request(
        val method: String,
        val path: String,
        val headers: Map<String, String>,
    )

    private val socket = ServerSocket(0, 50, InetAddress.getByName("127.0.0.1"))
    val port: Int get() = socket.localPort

    init {
        thread(isDaemon = true, name = "mini-http-accept") {
            while (!socket.isClosed) {
                val client = runCatching { socket.accept() }.getOrNull() ?: break
                thread(isDaemon = true, name = "mini-http-client") { serve(client) }
            }
        }
    }

    private fun serve(client: Socket) {
        client.use {
            val input = BufferedInputStream(it.getInputStream())
            val lines = mutableListOf<String>()
            while (true) {
                val line = readLine(input) ?: return
                if (line.isEmpty()) break
                lines += line
            }
            val parts = lines.firstOrNull()?.split(" ") ?: return
            val headers =
                lines.drop(1).associate { header ->
                    header.substringBefore(':').trim().lowercase() to header.substringAfter(':').trim()
                }
            val length = headers["content-length"]?.toIntOrNull() ?: 0
            repeat(length) { input.read() }
            handler(Request(parts[0], parts.getOrElse(1) { "/" }, headers), it.getOutputStream())
            it.getOutputStream().flush()
        }
    }

    private fun readLine(input: BufferedInputStream): String? {
        val bytes = java.io.ByteArrayOutputStream()
        while (true) {
            val b = input.read()
            if (b < 0) return if (bytes.size() == 0) null else bytes.toString("UTF-8")
            if (b == '\n'.code) return bytes.toString("UTF-8").trimEnd('\r')
            bytes.write(b)
        }
    }

    override fun close() {
        socket.close()
    }
}

fun OutputStream.respond(
    status: Int,
    body: String,
    headers: Map<String, String> = emptyMap(),
) {
    val bytes = body.toByteArray(Charsets.UTF_8)
    val head = StringBuilder("HTTP/1.1 $status X\r\nContent-Type: application/json\r\nContent-Length: ${bytes.size}\r\nConnection: close\r\n")
    headers.forEach { (name, value) -> head.append("$name: $value\r\n") }
    head.append("\r\n")
    write(head.toString().toByteArray())
    write(bytes)
    flush()
}
