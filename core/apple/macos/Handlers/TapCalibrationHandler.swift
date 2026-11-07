import Foundation

struct TapCalibrationHandler {
    func register(on router: Router) {
        router.register("get-tap-calibration") { _ in getCalibration() }
        router.register("set-tap-calibration") { body in setCalibration(body) }
    }

    private func getCalibration() -> [String: Any] {
        successResponse(TapCalibrationStore.current().responsePayload)
    }

    private func setCalibration(_ body: [String: Any]) -> [String: Any] {
        guard let offsetX = double(body["offsetX"]),
              let offsetY = double(body["offsetY"]),
              offsetX.isFinite,
              offsetY.isFinite else {
            return errorResponse(
                code: "MISSING_PARAM",
                message: "offsetX and offsetY are required numbers"
            )
        }
        return successResponse(TapCalibrationStore.save(offsetX: offsetX, offsetY: offsetY).responsePayload)
    }

    private func double(_ value: Any?) -> Double? {
        (value as? NSNumber)?.doubleValue
    }
}
