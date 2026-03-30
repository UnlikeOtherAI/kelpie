import UIKit

/// Collects device metadata for mDNS TXT records and /v1/get-device-info.
struct DeviceInfo {
    let id: String
    let name: String
    let model: String
    let platform: String = "ios"
    let width: Int
    let height: Int
    let port: Int
    let version: String

    static func current(port: Int) -> DeviceInfo {
        let device = UIDevice.current
        let screen = UIScreen.main
        let bounds = screen.bounds
        let scale = screen.scale
        return DeviceInfo(
            id: DeviceIdentity.id,
            name: device.name,
            model: modelIdentifier(),
            width: Int(bounds.width * scale),
            height: Int(bounds.height * scale),
            port: port,
            version: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0"
        )
    }

    var txtRecord: [String: String] {
        [
            "id": id,
            "name": name,
            "model": model,
            "platform": platform,
            "width": String(width),
            "height": String(height),
            "port": String(port),
            "version": version,
        ]
    }

    private static func modelIdentifier() -> String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let mirror = Mirror(reflecting: systemInfo.machine)
        let identifier = mirror.children.compactMap { $0.value as? Int8 }
            .filter { $0 != 0 }
            .map { String(UnicodeScalar(UInt8($0))) }
            .joined()
        return identifier.isEmpty ? UIDevice.current.model : identifier
    }
}
