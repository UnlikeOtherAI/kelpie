package com.kelpie.browser.browser

import android.os.Handler
import android.os.Looper
import android.webkit.JsPromptResult
import android.webkit.JsResult

class DialogState {
    data class PendingDialog(
        val type: String,
        val message: String,
        val defaultText: String?,
        val jsResult: JsResult?,
        val jsPromptResult: JsPromptResult?,
    )

    private val mainHandler = Handler(Looper.getMainLooper())
    private val lock = Any()

    @Volatile
    var current: PendingDialog? = null
        private set

    @Volatile
    var autoHandler: String? = null

    @Volatile
    var autoPromptText: String = ""

    fun enqueue(dialog: PendingDialog) {
        val mode = autoHandler
        if (mode != null) {
            resolve(dialog, mode, null)
            return
        }

        val existing =
            synchronized(lock) {
                val pending = current
                current = dialog
                pending
            }
        existing?.let { resolve(it, "dismiss", null) }
    }

    fun handle(
        action: String,
        text: String? = null,
    ): PendingDialog? {
        val dialog =
            synchronized(lock) {
                val pending = current ?: return null
                current = null
                pending
            }
        resolve(dialog, action, text)
        return dialog
    }

    fun dismissPending() {
        val dialog =
            synchronized(lock) {
                val pending = current ?: return
                current = null
                pending
            }
        resolve(dialog, "dismiss", null)
    }

    private fun resolve(
        dialog: PendingDialog,
        action: String,
        text: String?,
    ) {
        val work =
            Runnable {
                if (action == "accept") {
                    if (dialog.type == "prompt") {
                        val responseText = text ?: autoPromptText.takeIf { it.isNotEmpty() } ?: dialog.defaultText ?: ""
                        dialog.jsPromptResult?.confirm(responseText)
                    } else {
                        dialog.jsPromptResult?.confirm()
                        dialog.jsResult?.confirm()
                    }
                } else {
                    dialog.jsPromptResult?.cancel()
                    dialog.jsResult?.cancel()
                }
            }

        if (Looper.myLooper() == Looper.getMainLooper()) {
            work.run()
        } else {
            mainHandler.post(work)
        }
    }
}
