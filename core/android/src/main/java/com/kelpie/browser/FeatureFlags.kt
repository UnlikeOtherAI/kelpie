package com.kelpie.browser

import android.content.Context

object FeatureFlags {
    private const val PREFS_NAME = "kelpie_feature_flags"
    private const val KEY_ENABLE_3D_INSPECTOR = "enable3DInspector"

    fun is3DInspectorEnabled(context: Context): Boolean {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        return if (prefs.contains(KEY_ENABLE_3D_INSPECTOR)) {
            prefs.getBoolean(KEY_ENABLE_3D_INSPECTOR, true)
        } else {
            System.getenv("KELPIE_3D_INSPECTOR") != "0"
        }
    }

    fun set3DInspectorEnabled(
        context: Context,
        enabled: Boolean,
    ) {
        context
            .getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit()
            .putBoolean(KEY_ENABLE_3D_INSPECTOR, enabled)
            .apply()
    }
}
