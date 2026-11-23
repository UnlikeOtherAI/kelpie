package com.kelpie.browser.browser

import android.app.Activity
import android.app.AlertDialog
import android.content.ActivityNotFoundException
import android.webkit.WebResourceRequest
import android.webkit.WebView
import android.widget.Toast
import java.util.WeakHashMap

/**
 * Asks before a page hands a link to another app. Only a page's main frame may ask; with a gesture
 * it may always ask, otherwise once per document, which covers launch pages that redirect to their
 * app on load without letting a page loop the prompt.
 */
internal class ExternalAppPrompt(
    private val activity: Activity,
) {
    private val askedWithoutGesture = WeakHashMap<WebView, Boolean>()
    private var dialog: AlertDialog? = null

    /** A new document may ask once again. */
    fun documentStarted(view: WebView) {
        askedWithoutGesture.remove(view)
    }

    /** `true` when [request] is an app link, which the WebView must never load itself. */
    fun intercept(
        view: WebView,
        request: WebResourceRequest,
    ): Boolean {
        if (!ExternalAppLinks.isAppLink(request.url)) return false
        if (!request.isForMainFrame) return true
        if (!request.hasGesture()) {
            if (askedWithoutGesture[view] == true) return true
            askedWithoutGesture[view] = true
        }
        val url = request.url.toString()
        val intent = ExternalAppLinks.intentFor(url) ?: return true
        if (!view.isShown || dialog?.isShowing == true || activity.isFinishing || activity.isDestroyed) return true
        val requester = ExternalAppLinks.origin(view.url) ?: "This page"
        dialog =
            AlertDialog
                .Builder(activity)
                .setTitle("Open in another app?")
                .setMessage("$requester wants to open a “${request.url.scheme}:” link in another app.")
                .setNegativeButton("Cancel", null)
                .setPositiveButton("Open") { _, _ ->
                    if (view.isShown) launch(view, url, intent)
                }.show()
        return true
    }

    private fun launch(
        view: WebView,
        url: String,
        intent: android.content.Intent,
    ) {
        try {
            activity.startActivity(intent)
        } catch (_: ActivityNotFoundException) {
            val fallback = ExternalAppLinks.fallbackUrl(url)
            if (fallback != null) {
                view.loadUrl(fallback)
            } else {
                Toast.makeText(activity, "No app can open this link", Toast.LENGTH_SHORT).show()
            }
        }
    }
}
