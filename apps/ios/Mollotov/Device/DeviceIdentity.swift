import Foundation
import UIKit
import Security

/// Provides a stable device UUID that persists across app installs.
enum DeviceIdentity {
    private static let keychainKey = "com.mollotov.device-id"

    static var id: String {
        if let stored = readFromKeychain() { return stored }
        let newId = UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
        saveToKeychain(newId)
        return newId
    }

    private static func readFromKeychain() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: keychainKey,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func saveToKeychain(_ value: String) {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: keychainKey,
            kSecValueData as String: data,
        ]
        SecItemDelete(query as CFDictionary)
        SecItemAdd(query as CFDictionary, nil)
    }
}
