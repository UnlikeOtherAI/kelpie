import Foundation
import Security
import UIKit

/// Provides a stable device UUID that persists across app launches.
/// Stored in `UserDefaults`. Older builds wrote the value to Keychain;
/// the first read after upgrade migrates it out of Keychain and removes
/// the legacy entry so subsequent reads never touch Security.framework.
enum DeviceIdentity {
    private static let defaultsKey = "com.kelpie.device-id"

    static var id: String {
        if let stored = UserDefaults.standard.string(forKey: defaultsKey), !stored.isEmpty {
            return stored
        }
        if let migrated = migrateFromKeychain() {
            UserDefaults.standard.set(migrated, forKey: defaultsKey)
            return migrated
        }
        let newId = UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
        UserDefaults.standard.set(newId, forKey: defaultsKey)
        return newId
    }

    /// One-time backward-compat read of the legacy Keychain entry.
    /// Returns the stored value (if any) and removes the Keychain entry
    /// so the app never reads from Keychain again.
    private static func migrateFromKeychain() -> String? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrAccount: defaultsKey,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data,
              let value = String(data: data, encoding: .utf8), !value.isEmpty else {
            return nil
        }
        let deleteQuery: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrAccount: defaultsKey
        ]
        SecItemDelete(deleteQuery as CFDictionary)
        return value
    }
}
