package com.kelpie.browser.browser

import android.content.ActivityNotFoundException
import android.content.ContentResolver
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Process
import android.webkit.ValueCallback
import android.webkit.WebChromeClient.FileChooserParams
import android.webkit.WebView
import androidx.activity.ComponentActivity
import androidx.activity.result.ActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import java.util.UUID

/** Hands a tab's file input to Android's document picker. */
internal class WebFileChooser(
    private val activity: ComponentActivity,
) {
    private class Request(
        val view: WebView,
        val callback: ValueCallback<Array<Uri>>,
    )

    private var request: Request? = null
    private var pickerInFlight = false
    private val launcher =
        activity.activityResultRegistry.register(
            "kelpie.upload.${UUID.randomUUID()}",
            ActivityResultContracts.StartActivityForResult(),
            ::complete,
        )

    fun show(
        view: WebView,
        callback: ValueCallback<Array<Uri>>,
        params: FileChooserParams,
    ): Boolean {
        if (pickerInFlight) return false
        if (params.mode != FileChooserParams.MODE_OPEN && params.mode != FileChooserParams.MODE_OPEN_MULTIPLE) {
            return false
        }
        // Keep WebView's MIME filters and multiple-selection flag.
        val intent = params.createIntent().setAction(Intent.ACTION_OPEN_DOCUMENT)
        request = Request(view, callback)
        pickerInFlight = true
        return try {
            launcher.launch(intent)
            true
        } catch (_: ActivityNotFoundException) {
            request = null
            pickerInFlight = false
            false
        }
    }

    fun cancel(view: WebView) {
        val pending = request?.takeIf { it.view === view } ?: return
        // Wait for this picker to return before accepting another request.
        request = null
        pending.callback.onReceiveValue(null)
    }

    fun close() {
        request?.let { cancel(it.view) }
        launcher.unregister()
    }

    private fun complete(result: ActivityResult) {
        val pending = request
        request = null
        pickerInFlight = false
        if (pending == null) return
        // WebView's parser reads Intent.data only. AndroidX also reads the ClipData used for multiple files.
        val selected = ActivityResultContracts.OpenMultipleDocuments().parseResult(result.resultCode, result.data)
        pending.callback.onReceiveValue(selected.takeIf { it.isNotEmpty() && it.all(::hasReadGrant) }?.toTypedArray())
    }

    private fun hasReadGrant(uri: Uri): Boolean =
        uri.scheme == ContentResolver.SCHEME_CONTENT &&
            activity.checkUriPermission(
                uri,
                Process.myPid(),
                Process.myUid(),
                Intent.FLAG_GRANT_READ_URI_PERMISSION,
            ) == PackageManager.PERMISSION_GRANTED
}
