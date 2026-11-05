package com.kelpie.browser.ui

import android.app.Activity
import android.content.pm.ActivityInfo
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect

/** Recording owns presentation geometry until normal terminal UI restoration. */
@Composable
internal fun RecordingOrientationEffect(
    activity: Activity,
    recording: Boolean,
) {
    DisposableEffect(activity, recording) {
        val previous = activity.requestedOrientation
        if (recording) activity.requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_LOCKED
        onDispose {
            if (recording) activity.requestedOrientation = previous
        }
    }
}
