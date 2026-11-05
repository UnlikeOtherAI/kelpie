package com.kelpie.browser.ui

import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.SideEffect
import com.kelpie.browser.handlers.HandlerContext

/** A committed recording scene is eligible only when every other layer is absent. */
internal fun scriptSceneCertified(
    recording: Boolean,
    occluders: List<Boolean>,
): Boolean = recording && occluders.none { it }

@Composable
internal fun ScriptCaptureSceneEffect(
    context: HandlerContext,
    recording: Boolean,
    occluders: List<Boolean>,
) {
    val certified = scriptSceneCertified(recording, occluders)
    SideEffect { context.scriptCaptureScene = certified }
    DisposableEffect(context) { onDispose { context.scriptCaptureScene = false } }
}
