import Foundation

/// Account job results are bounded by the connect ledger (768 KiB serialized).
/// A viewport PNG of a photographic or large page can exceed that once base64
/// encoded, so account screenshots recapture as progressively smaller JPEGs.
/// The native result reports its real format, so the typed image stays truthful.
enum ConnectScreenshotBudget {
    /// Base64 characters, leaving headroom for the canonical envelope and pins.
    static let maxImageCharacters = 640 * 1024
    static let jpegQualities = [80, 60, 40]

    typealias Capture = ([String: Any]) async -> [String: Any]

    static func fit(_ params: [String: Any], capture: Capture) async -> [String: Any] {
        let first = await capture(params)
        guard oversized(first) else { return first }
        for quality in fallbackQualities(after: params) {
            var jpeg = params
            jpeg["format"] = "jpeg"
            jpeg["quality"] = quality
            let result = await capture(jpeg)
            guard oversized(result) else { return result }
        }
        return errorResponse(
            code: "SCREENSHOT_TOO_LARGE",
            message: "The screenshot exceeds the account result limit even as a JPEG."
        )
    }

    /// A capture that already was a JPEG only retries at lower qualities.
    private static func fallbackQualities(after params: [String: Any]) -> [Int] {
        guard params["format"] as? String == "jpeg" else { return jpegQualities }
        let initial = (params["quality"] as? NSNumber)?.intValue ?? 80
        return jpegQualities.filter { $0 < initial }
    }

    /// Only a successful capture can be oversized; failures and fence refusals return unchanged.
    private static func oversized(_ result: [String: Any]) -> Bool {
        guard result["success"] as? Bool == true, let image = result["image"] as? String else { return false }
        return image.utf8.count > maxImageCharacters
    }
}
