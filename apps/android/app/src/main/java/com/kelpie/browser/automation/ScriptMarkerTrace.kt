package com.kelpie.browser.automation

import android.util.Log
import com.kelpie.browser.BuildConfig

/** Fixed diagnostic categories only; no page, target or authority contents. */
internal fun scriptMarkerTrace(
    stage: String,
    reason: String,
) {
    if (BuildConfig.DEBUG) Log.d("KelpieMarkerTrace", "stage=" + stage + " reason=" + reason + " nowNs=" + System.nanoTime())
}
