package com.kelpie.browser.ui

import android.content.Context
import android.view.KeyEvent
import android.widget.FrameLayout

internal fun blocksScriptBrowserKey(
    active: Boolean,
    system: Boolean,
): Boolean = active && !system

/** Blocks hardware keys routed to the native renderer while a script owns input. */
internal class ScriptRendererKeyFrame(
    context: Context,
    private val scriptActive: () -> Boolean,
) : FrameLayout(context) {
    override fun dispatchKeyEvent(event: KeyEvent): Boolean {
        if (blocksScriptBrowserKey(scriptActive(), event.isSystem)) return true
        return super.dispatchKeyEvent(event)
    }
}
