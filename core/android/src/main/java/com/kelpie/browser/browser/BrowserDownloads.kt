package com.kelpie.browser.browser

import android.net.Uri
import android.webkit.CookieManager
import android.webkit.MimeTypeMap
import android.webkit.WebView
import androidx.compose.runtime.mutableStateListOf
import androidx.webkit.URLUtilCompat
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import okhttp3.HttpUrl.Companion.toHttpUrl
import okhttp3.OkHttpClient
import okhttp3.Request
import java.io.IOException
import java.io.OutputStream
import java.util.UUID

internal data class BrowserDownload(
    val id: String,
    val name: String,
    val mime: String,
    val uri: Uri? = null,
    val error: String? = null,
) {
    val finished: Boolean get() = uri != null || error != null
}

internal object BrowserDownloads {
    val items = mutableStateListOf<BrowserDownload>()
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private val client = OkHttpClient.Builder().followRedirects(false).build()

    fun attach(view: WebView) {
        view.setDownloadListener { url, agent, disposition, mime, _ ->
            val suggested = disposition?.let(URLUtilCompat::getFilenameFromContentDisposition) ?: URLUtilCompat.guessFileName(url, null, mime)
            val name = safeDownloadName(suggested)
            val extensionType = MimeTypeMap.getSingleton().getMimeTypeFromExtension(name.substringAfterLast('.', "").lowercase())
            val type = mime?.takeUnless { it.isBlank() || it == "application/octet-stream" } ?: extensionType ?: "application/octet-stream"
            val item = BrowserDownload(UUID.randomUUID().toString(), name, type)
            val cookies = PartitionRegistry.cookies(view)
            val context = view.context.applicationContext
            items.add(0, item)
            scope.launch {
                val result =
                    runCatching {
                        saveDownload(context, item) { output ->
                            when (Uri.parse(url).scheme) {
                                "http", "https" -> copyHttp(url, agent, cookies, output)
                                "blob", "data" -> copyPageDownload(view, url, output)
                                else -> throw IOException("Unsupported download address")
                            }
                        }
                    }
                val index = items.indexOfFirst { it.id == item.id }
                if (index >= 0) {
                    items[index] =
                        result.fold(
                            onSuccess = { item.copy(uri = it) },
                            onFailure = { item.copy(error = it.localizedMessage ?: "Download interrupted") },
                        )
                }
                while (items.size > 200) {
                    val oldest = items.indexOfLast { it.finished }
                    if (oldest < 0) break
                    items.removeAt(oldest)
                }
            }
        }
    }

    fun clearFinished() {
        items.removeAll { it.finished }
    }

    private suspend fun copyHttp(
        address: String,
        userAgent: String?,
        cookies: CookieManager,
        output: OutputStream,
    ) {
        val initial = address.toHttpUrl()
        var url = initial
        repeat(21) {
            val request = Request.Builder().url(url)
            if (!userAgent.isNullOrBlank()) request.header("User-Agent", userAgent)
            if (url.scheme == initial.scheme && url.host == initial.host && url.port == initial.port) {
                withContext(Dispatchers.Main) { cookies.getCookie(url.toString()) }?.let { request.header("Cookie", it) }
            }
            client.newCall(request.build()).execute().use { response ->
                if (response.code in setOf(301, 302, 303, 307, 308)) {
                    val target = response.header("Location")?.let(url::resolve) ?: throw IOException("Invalid download redirect")
                    if (url.isHttps && !target.isHttps) throw IOException("Download redirected to an insecure connection")
                    url = target
                } else {
                    if (!response.isSuccessful) throw IOException("Download returned HTTP ${response.code}")
                    val body = response.body ?: throw IOException("Missing download body")
                    body.byteStream().copyTo(output)
                    return
                }
            }
        }
        throw IOException("Too many download redirects")
    }
}
