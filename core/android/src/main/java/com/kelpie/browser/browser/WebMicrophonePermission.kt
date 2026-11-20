package com.kelpie.browser.browser

import android.Manifest
import android.app.AlertDialog
import android.content.pm.PackageManager
import android.webkit.PermissionRequest
import android.webkit.WebView
import androidx.activity.ComponentActivity
import androidx.activity.result.contract.ActivityResultContracts
import androidx.core.content.ContextCompat
import com.kelpie.browser.network.isLoopbackHost
import java.util.UUID

/** Prompts for site access before requesting Android's app-level microphone permission. */
internal class WebMicrophonePermission(
    private val activity: ComponentActivity,
    private val isActive: (WebView) -> Boolean,
) {
    private class Pending(
        val view: WebView,
        val request: PermissionRequest,
    ) {
        var dialog: AlertDialog? = null
    }

    private var pending: Pending? = null
    private var systemPromptInFlight = false
    private val launcher =
        activity.activityResultRegistry.register(
            "kelpie.microphone.${UUID.randomUUID()}",
            ActivityResultContracts.RequestPermission(),
        ) { granted ->
            systemPromptInFlight = false
            pending?.let { complete(it, granted) }
        }

    fun show(
        view: WebView,
        request: PermissionRequest,
    ) {
        val origin = request.origin
        val secure =
            !origin.host.isNullOrEmpty() &&
                (origin.scheme == "https" || (origin.scheme == "http" && origin.host?.let(::isLoopbackHost) == true))
        if (!secure ||
            request.resources.toList() != listOf(PermissionRequest.RESOURCE_AUDIO_CAPTURE) ||
            pending != null ||
            systemPromptInFlight ||
            !isActive(view) ||
            activity.isFinishing ||
            activity.isDestroyed
        ) {
            request.deny()
            return
        }

        val next = Pending(view, request)
        pending = next
        next.dialog =
            AlertDialog
                .Builder(activity)
                .setTitle("Allow microphone access?")
                .setMessage("$origin wants to use your microphone.")
                .setNegativeButton("Deny") { _, _ -> complete(next, false) }
                .setPositiveButton("Allow") { _, _ -> requestAndroidPermission(next) }
                .setOnCancelListener { complete(next, false) }
                .show()
    }

    fun cancel(view: WebView) {
        pending?.takeIf { it.view === view }?.let { complete(it, false) }
    }

    fun requestCanceled(request: PermissionRequest) {
        // WebView has already canceled this request, so no grant/deny is due.
        val current = pending?.takeIf { it.request === request } ?: return
        pending = null
        current.dialog?.dismiss()
    }

    fun close() {
        pending?.let { complete(it, false) }
        launcher.unregister()
    }

    private fun requestAndroidPermission(current: Pending) {
        if (pending !== current) return
        if (!isActive(current.view)) {
            complete(current, false)
            return
        }
        if (ContextCompat.checkSelfPermission(activity, Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED) {
            complete(current, true)
            return
        }
        systemPromptInFlight = true
        launcher.launch(Manifest.permission.RECORD_AUDIO)
    }

    private fun complete(
        current: Pending,
        allowed: Boolean,
    ) {
        if (pending !== current) return
        pending = null
        current.dialog?.dismiss()
        if (allowed && isActive(current.view)) {
            current.request.grant(arrayOf(PermissionRequest.RESOURCE_AUDIO_CAPTURE))
        } else {
            current.request.deny()
        }
    }
}
