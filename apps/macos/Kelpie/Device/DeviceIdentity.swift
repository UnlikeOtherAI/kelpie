import Foundation
import IOKit

/// Provides a stable device UUID that persists across app launches.
/// Uses UserDefaults and falls back to the hardware UUID when first created.
enum DeviceIdentity {
    private static let defaultsKey = "com.kelpie.device-id"

    static var id: String {
        if let stored = UserDefaults.standard.string(forKey: defaultsKey), !stored.isEmpty {
            return stored
        }
        let newId = hardwareUUID() ?? UUID().uuidString
        UserDefaults.standard.set(newId, forKey: defaultsKey)
        return newId
    }

    private static func hardwareUUID() -> String? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPlatformExpertDevice"))
        defer { IOObjectRelease(service) }

        guard service != 0 else { return nil }
        let uuid = IORegistryEntryCreateCFProperty(
            service,
            "IOPlatformUUID" as CFString,
            kCFAllocatorDefault,
            0
        )
        return uuid?.takeRetainedValue() as? String
    }
}
