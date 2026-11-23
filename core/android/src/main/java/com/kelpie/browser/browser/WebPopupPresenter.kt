package com.kelpie.browser.browser

import android.annotation.SuppressLint
import android.app.Activity
import android.app.Dialog
import android.net.Uri
import android.os.Message
import android.view.ViewGroup
import android.webkit.WebChromeClient
import android.webkit.WebView
import android.webkit.WebViewClient
import android.widget.Button
import android.widget.LinearLayout
import android.widget.TextView

/** Presents the WebView paired with the Chromium opener by WebViewTransport. */
internal class WebPopupPresenter(
    private val activity: Activity,
    private val externalApps: ExternalAppPrompt?,
    private val openTab: (partition: String?, result: Message) -> Boolean,
) {
    private data class Popup(
        val opener: WebView,
        val dialog: Dialog,
    )

    private val popups = mutableMapOf<WebView, Popup>()

    @SuppressLint("SetJavaScriptEnabled")
    fun open(
        opener: WebView,
        partition: String?,
        result: Message,
    ): Boolean {
        val transport = result.obj as? WebView.WebViewTransport ?: return false
        if (activity.isFinishing || activity.isDestroyed || !opener.isShown) return false
        val profile = partition?.let { PartitionRegistry.resolve(it, restoring = true) }
        val view = WebView(activity)
        PartitionRegistry.bind(view, profile)
        BrowserDownloads.attach(view)
        view.settings.apply {
            javaScriptEnabled = opener.settings.javaScriptEnabled
            domStorageEnabled = opener.settings.domStorageEnabled
            userAgentString = opener.settings.userAgentString
            javaScriptCanOpenWindowsAutomatically = true
            setSupportMultipleWindows(true)
        }
        val dialog = Dialog(activity)
        val origin = TextView(activity).apply { text = "Pop-up" }
        val close =
            Button(activity).apply {
                text = "Close"
                contentDescription = "Close pop-up"
                setOnClickListener { dialog.dismiss() }
            }
        val bar =
            LinearLayout(activity).apply {
                addView(origin, LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f))
                addView(close)
            }
        val content =
            LinearLayout(activity).apply {
                orientation = LinearLayout.VERTICAL
                addView(bar)
                addView(view, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, 0, 1f))
            }
        view.webViewClient =
            object : WebViewClient() {
                override fun onPageStarted(
                    view: WebView,
                    url: String,
                    favicon: android.graphics.Bitmap?,
                ) {
                    externalApps?.documentStarted(view)
                }

                override fun shouldOverrideUrlLoading(
                    view: WebView,
                    request: android.webkit.WebResourceRequest,
                ): Boolean = externalApps?.intercept(view, request) ?: ExternalAppLinks.isAppLink(request.url)

                override fun onPageCommitVisible(
                    view: WebView,
                    url: String,
                ) {
                    val uri = Uri.parse(url)
                    val host = uri.host
                    origin.text =
                        if (host != null && (uri.scheme == "https" || uri.scheme == "http")) {
                            val port = if (uri.port == -1) "" else ":${uri.port}"
                            "${uri.scheme}://$host$port"
                        } else {
                            "Pop-up"
                        }
                }
            }
        view.webChromeClient =
            object : WebChromeClient() {
                override fun onCreateWindow(
                    view: WebView,
                    isDialog: Boolean,
                    isUserGesture: Boolean,
                    resultMsg: Message,
                ): Boolean = if (isDialog) open(view, partition, resultMsg) else openTab(partition, resultMsg)

                override fun onCloseWindow(window: WebView) = dialog.dismiss()
            }
        dialog.setContentView(content)
        dialog.setOnDismissListener {
            popups.remove(view)
            closeFor(view)
            content.removeView(view)
            view.destroy()
        }
        popups[view] = Popup(opener, dialog)
        dialog.show()
        dialog.window?.setLayout(
            ViewGroup.LayoutParams.MATCH_PARENT,
            (activity.resources.displayMetrics.heightPixels * 0.9).toInt(),
        )
        transport.webView = view
        result.sendToTarget()
        return true
    }

    fun closeFor(opener: WebView) {
        popups.values.filter { it.opener === opener }.forEach { it.dialog.dismiss() }
    }
}
