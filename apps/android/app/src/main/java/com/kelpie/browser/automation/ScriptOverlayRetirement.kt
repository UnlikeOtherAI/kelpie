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
        val job =
            CoroutineScope(SupervisorJob() + Dispatchers.Default).launch {
                try {
                    while (overlay.isRetained(retained)) {
                        val remaining = retained.deadlineNs - System.nanoTime()
                        if (remaining <= 0) {
                            scriptMarkerTrace("poll", "EXPIRED")
                            break
                        }
                        val timeoutMs = ((remaining + 999_999) / 1_000_000).coerceIn(1, 100)
                        val permitted = withTimeoutOrNull(timeoutMs) { authority.permits() }
                        if (permitted != true) {
                            scriptMarkerTrace("poll", if (permitted == null) "GRANT_TIMEOUT" else "GRANT_DENIED")
                            break
                        }
                        val valid =
                            withContext(Dispatchers.Main.immediate) {
                                val reason =
                                    when {
                                        !overlay.isRetained(retained) -> "OWNER_CHANGED"
                                        !runCatching { authority.permitsOnMain() }.getOrDefault(false) -> "GRANT_REVOKED"
                                        !context.scriptForeground -> "BACKGROUND"
                                        context.tabStore?.activeTabId?.value != tabId -> "TAB_CHANGED"
                                        context.tabStore?.activeTab?.webView !== view -> "VIEW_CHANGED"
                                        context.tabStore?.activeTab?.documentVersion != retained.document -> "DOCUMENT_CHANGED"
                                        context.scriptPlaybackState?.isRecording?.value == true -> "PLAYBACK_ACTIVE"
                                        !view.isAttachedToWindow -> "DETACHED"
                                        !view.isShown -> "HIDDEN"
                                        !view.hasWindowFocus() -> "WINDOW_FOCUS_LOST"
                                        view.rootView !== root -> "ROOT_CHANGED"
                                        view.windowToken !== windowToken -> "WINDOW_CHANGED"
                                        else -> null
                                    }
                                if (reason != null) scriptMarkerTrace("pollGuard", reason)
                                reason == null
                            }
                        if (!valid) {
                            scriptMarkerTrace("poll", "SYNC_GUARD_FAILED")
                            break
                        }
                        val delayMs = ((retained.deadlineNs - System.nanoTime()) / 1_000_000).coerceIn(1, 25)
                        delay(delayMs)
                    }
                } finally {
                    withContext(Dispatchers.Main.immediate) { overlay.clearRetained(retained) }
                }
            }
        overlay.installRetirementJob(retained, job)
    }
}
