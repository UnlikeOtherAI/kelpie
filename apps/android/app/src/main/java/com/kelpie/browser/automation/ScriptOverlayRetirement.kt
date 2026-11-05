package com.kelpie.browser.automation

import android.os.IBinder
import android.view.View
import android.webkit.WebView
import com.kelpie.browser.handlers.HandlerContext
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull

/** Retains one successful final tap without keeping a workflow or Stop active. */
internal object ScriptOverlayRetirement {
    fun start(
        overlay: ScriptOverlay,
        retained: ScriptOverlay.RetainedTap,
        authority: ScriptAuthority,
        context: HandlerContext,
        tabId: String,
        view: WebView,
        root: View,
        windowToken: IBinder,
    ) {
        CoroutineScope(SupervisorJob() + Dispatchers.Default).launch {
            try {
                while (overlay.isRetained(retained)) {
                    val remaining = retained.deadlineNs - System.nanoTime()
                    if (remaining <= 0) break
                    val timeoutMs = ((remaining + 999_999) / 1_000_000).coerceIn(1, 100)
                    if (withTimeoutOrNull(timeoutMs) { authority.permits() } != true) break
                    val valid =
                        withContext(Dispatchers.Main.immediate) {
                            overlay.isRetained(retained) &&
                                runCatching { authority.permitsOnMain() }.getOrDefault(false) &&
                                context.scriptForeground &&
                                context.tabStore?.activeTabId?.value == tabId &&
                                context.tabStore?.activeTab?.webView === view &&
                                context.tabStore?.activeTab?.documentVersion == retained.document &&
                                context.scriptPlaybackState?.isRecording?.value != true &&
                                view.isAttachedToWindow && view.isShown && view.hasWindowFocus() &&
                                view.rootView === root && view.windowToken === windowToken
                        }
                    if (!valid) break
                    val delayMs = ((retained.deadlineNs - System.nanoTime()) / 1_000_000).coerceIn(1, 25)
                    delay(delayMs)
                }
            } finally {
                withContext(Dispatchers.Main.immediate) { overlay.clearRetained(retained) }
            }
        }
    }
}