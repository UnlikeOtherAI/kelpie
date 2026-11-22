package com.kelpie.browser.browser

import android.content.ContentValues
import android.content.Context
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import androidx.core.content.FileProvider
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.File
import java.io.IOException
import java.io.OutputStream

internal fun safeDownloadName(name: String): String =
    name
        .substringAfterLast('/')
        .substringAfterLast('\\')
        .filter { it.code >= 32 && it != '\u007f' }
        .trim()
        .trimStart('.')
        .take(180)
        .ifBlank { "download" }

internal suspend fun saveDownload(
    context: Context,
    item: BrowserDownload,
    copy: suspend (OutputStream) -> Unit,
): Uri =
    withContext(Dispatchers.IO) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val resolver = context.contentResolver
            val values =
                ContentValues().apply {
                    put(MediaStore.Downloads.DISPLAY_NAME, item.name)
                    put(MediaStore.Downloads.MIME_TYPE, item.mime)
                    put(MediaStore.Downloads.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS)
                    put(MediaStore.Downloads.IS_PENDING, 1)
                }
            val uri = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values) ?: throw IOException("Cannot create download")
            try {
                val stream = resolver.openOutputStream(uri) ?: throw IOException("Cannot open download")
                stream.use { copy(it) }
                values.clear()
                values.put(MediaStore.Downloads.IS_PENDING, 0)
                if (resolver.update(uri, values, null, null) != 1) throw IOException("Cannot publish download")
                uri
            } catch (error: Throwable) {
                resolver.delete(uri, null, null)
                throw error
            }
        } else {
            val dir = context.getExternalFilesDir(Environment.DIRECTORY_DOWNLOADS) ?: throw IOException("Downloads unavailable")
            val original = File(dir, item.name)
            var file = original
            var suffix = 1
            while (!file.createNewFile()) {
                val ext = original.extension.let { if (it.isEmpty()) "" else ".$it" }
                file = File(dir, "${original.nameWithoutExtension} (${suffix++})$ext")
            }
            try {
                file.outputStream().use { copy(it) }
                FileProvider.getUriForFile(context, "${context.packageName}.kelpie.downloads", file)
            } catch (error: Throwable) {
                file.delete()
                throw error
            }
        }
    }
