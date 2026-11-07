package com.kelpie.browser.handlers

import com.kelpie.browser.network.Router
import com.kelpie.browser.network.errorResponse
import com.kelpie.browser.network.successResponse

class TapCalibrationHandler {
    fun register(router: Router) {
        router.register("get-tap-calibration") { getCalibration() }
        router.register("set-tap-calibration") { body -> setCalibration(body) }
    }

    private fun getCalibration() =
        successResponse(
            mapOf(
                "offsetX" to TapCalibrationStore.current().offsetX,
                "offsetY" to TapCalibrationStore.current().offsetY,
            ),
        )

    private fun setCalibration(body: Map<String, Any?>): Map<String, Any?> {
        val offsetX = (body["offsetX"] as? Number)?.toDouble()
        val offsetY = (body["offsetY"] as? Number)?.toDouble()
        if (offsetX == null || offsetY == null || !offsetX.isFinite() || !offsetY.isFinite()) {
            return errorResponse("MISSING_PARAM", "offsetX and offsetY are required numbers")
        }
        val saved = TapCalibrationStore.save(offsetX, offsetY)
        return successResponse(
            mapOf(
                "offsetX" to saved.offsetX,
                "offsetY" to saved.offsetY,
            ),
        )
    }
}
