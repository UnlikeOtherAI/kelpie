import AppKit
import Foundation

/// Collects device metadata for mDNS TXT records and /v1/get-device-info.
struct DeviceInfo {
    let id: String
    let name: String
    let model: String
    let platform: String = "macos"
    let width: Int
    let height: Int
    let scale: Double
    let port: Int
    let version: String
    let build: String

    private static let rendererEngineDefaultsKey = "com.kelpie.renderer-engine"

    static func current(port: Int) -> Self {
        // swiftlint:disable:next force_unwrapping
        let screen = NSScreen.main ?? NSScreen.screens.first!
        let scale = screen.backingScaleFactor
        let size = screen.frame.size
        return Self(
            id: DeviceIdentity.id,
            name: Host.current().localizedName ?? "Mac",
            model: modelIdentifier(),
            width: Int(size.width * scale),
            height: Int(size.height * scale),
            scale: scale,
            port: port,
            version: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0",
            build: Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        )
    }

    static func currentRendererEngine() -> String {
        let saved = UserDefaults.standard.string(forKey: rendererEngineDefaultsKey) ?? ""
        return ["webkit", "chromium"].contains(saved) ? saved : "webkit"
    }

    func txtRecord(engine: String = "webkit") -> [String: String] {
        [
            "id": id,
            "name": name,
            "model": model,
            "platform": platform,
            "width": String(width),
            "height": String(height),
            "port": String(port),
            "version": version,
            "engine": engine
        ]
    }

    private static func modelIdentifier() -> String {
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        guard size > 0 else { return "Mac" }

        var buffer = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.model", &buffer, &size, nil, 0)
        return String(cString: buffer)
    }
}
