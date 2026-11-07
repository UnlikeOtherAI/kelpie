import Foundation

struct TapCalibration {
    let offsetX: Double
    let offsetY: Double

    var responsePayload: [String: Any] {
        [
            "offsetX": offsetX,
            "offsetY": offsetY
        ]
    }
}

enum TapCalibrationStore {
    private static let offsetXKey = "tapCalibrationOffsetX"
    private static let offsetYKey = "tapCalibrationOffsetY"

    static func current() -> TapCalibration {
        let defaults = UserDefaults.standard
        return TapCalibration(
            offsetX: defaults.double(forKey: offsetXKey),
            offsetY: defaults.double(forKey: offsetYKey)
        )
    }

    @discardableResult
    static func save(offsetX: Double, offsetY: Double) -> TapCalibration {
        let defaults = UserDefaults.standard
        defaults.set(offsetX, forKey: offsetXKey)
        defaults.set(offsetY, forKey: offsetYKey)
        return TapCalibration(offsetX: offsetX, offsetY: offsetY)
    }
}
