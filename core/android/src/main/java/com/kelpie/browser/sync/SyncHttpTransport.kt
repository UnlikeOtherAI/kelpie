package com.kelpie.browser.sync

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.Dns
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import java.net.Inet6Address
import java.net.InetAddress
import java.util.concurrent.TimeUnit

/**
 * Plain HTTP to a peer's sync listener. IPv4 and global IPv6 go by literal;
 * a scoped link-local IPv6 address goes through a synthetic host name whose
 * [Dns] answer is the scoped address, because URLs cannot carry a zone id.
 * No cookies, caches, redirects or retries.
 */
class SyncHttpTransport : SyncTransport {
    private val base =
        OkHttpClient
            .Builder()
            .followRedirects(false)
            .followSslRedirects(false)
            .retryOnConnectionFailure(false)
            .connectTimeout(5, TimeUnit.SECONDS)
            .build()

    override suspend fun post(
        target: PeerTarget,
        path: String,
        body: String,
        session: String?,
        timeoutMs: Long,
    ): SyncTransport.Response =
        withContext(Dispatchers.IO) {
            var last: java.io.IOException? = null
            for (address in target.addresses) {
                try {
                    return@withContext send(address, target.port, path, body, session, timeoutMs)
                } catch (error: java.io.IOException) {
                    last = error
                }
            }
            throw last ?: java.io.IOException("no address")
        }

    private fun send(
        address: InetAddress,
        port: Int,
        path: String,
        body: String,
        session: String?,
        timeoutMs: Long,
    ): SyncTransport.Response {
        val scoped = address is Inet6Address && address.scopeId != 0
        val host =
            when {
                scoped -> SYNTHETIC_HOST
                address is Inet6Address -> "[${address.hostAddress?.substringBefore('%')}]"
                else -> address.hostAddress ?: throw java.io.IOException("no address")
            }
        val client =
            base
                .newBuilder()
                .callTimeout(timeoutMs, TimeUnit.MILLISECONDS)
                .readTimeout(timeoutMs, TimeUnit.MILLISECONDS)
                .apply {
                    if (scoped) {
                        dns(
                            object : Dns {
                                override fun lookup(hostname: String): List<InetAddress> = listOf(address)
                            },
                        )
                    }
                }.build()
        val request =
            Request
                .Builder()
                .url("http://$host:$port$path")
                .post(body.toRequestBody(JSON))
                .apply { if (session != null) header(SyncProtocol.SESSION_HEADER, session) }
                .build()
        client.newCall(request).execute().use { response ->
            val text = response.body?.let { readBounded(it) }.orEmpty()
            return SyncTransport.Response(response.code, text)
        }
    }

    private fun readBounded(body: okhttp3.ResponseBody): String {
        val source = body.source()
        source.request(MAX_RESPONSE_BYTES + 1)
        if (source.buffer.size > MAX_RESPONSE_BYTES) throw java.io.IOException("response too large")
        return source.buffer.readUtf8()
    }

    private companion object {
        val JSON = "application/json".toMediaType()
        const val SYNTHETIC_HOST = "peer.kelpie-sync.invalid"
        const val MAX_RESPONSE_BYTES = 8L * 1024 * 1024
    }
}
