package com.kelpie.browser.automation

/** Canonical generated schemas/readers and core-automation numerical model. */
object ScriptNative {
    init {
        System.loadLibrary("kelpie_jni")
    }

    external fun redactOutputs(request: String): String?

    external fun validate(script: String): String

    external fun targetExpression(options: String): String?

    external fun pointerPosition(
        fromX: Double,
        fromY: Double,
        toX: Double,
        toY: Double,
        curveS: Boolean,
        elapsedMs: Double,
        durationMs: Double,
    ): DoubleArray

    external fun tapPresentation(
        elapsedMs: Double,
        durationMs: Double,
        wobble: Boolean,
        fade: Boolean,
    ): DoubleArray
}
