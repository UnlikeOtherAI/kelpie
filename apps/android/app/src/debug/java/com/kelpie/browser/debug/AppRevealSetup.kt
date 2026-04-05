package com.kelpie.browser.debug

import android.app.Application
import android.util.Log

/**
 * Debug-only AppReveal setup.
 * When AppReveal dependency is added, replace the body with:
 *   AppReveal.start(app)
 */
object AppRevealSetup {
    fun configure(app: Application) {
        Log.d("AppReveal", "AppReveal setup placeholder — add dependency to enable")
    }
}
