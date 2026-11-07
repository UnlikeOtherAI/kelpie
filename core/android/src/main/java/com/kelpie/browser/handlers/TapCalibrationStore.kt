package com.kelpie.browser.handlers

import android.content.Context
import android.content.SharedPreferences

data class TapCalibration(
    val offsetX: Double,
    val offsetY: Double,
)

object TapCalibrationStore {
    private const val PREFS_NAME = "kelpie_prefs"
    private const val OFFSET_X_KEY = "tapCalibrationOffsetX"
    private const val OFFSET_Y_KEY = "tapCalibrationOffsetY"

    private lateinit var prefs: SharedPreferences

    fun init(context: Context) {
        prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
    }

    fun current(): TapCalibration =
        if (::prefs.isInitialized) {
            TapCalibration(
                offsetX = prefs.getString(OFFSET_X_KEY, null)?.toDoubleOrNull() ?: 0.0,
                offsetY = prefs.getString(OFFSET_Y_KEY, null)?.toDoubleOrNull() ?: 0.0,
            )
        } else {
            TapCalibration(offsetX = 0.0, offsetY = 0.0)
        }

    fun save(
        offsetX: Double,
        offsetY: Double,
    ): TapCalibration {
        val editor = prefs.edit()
        editor.putString(OFFSET_X_KEY, offsetX.toString())
        editor.putString(OFFSET_Y_KEY, offsetY.toString())
        editor.apply()
        return TapCalibration(offsetX = offsetX, offsetY = offsetY)
    }
}
