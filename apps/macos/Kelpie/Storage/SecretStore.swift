import CryptoKit
import Foundation

/// Encrypted on-disk store for sensitive strings (API tokens, credentials).
///
/// Storage format:
/// - Ciphertext file at `<AppSupport>/Kelpie/secrets.enc` containing AES-GCM
///   sealed bytes whose plaintext is a JSON `[String: String]` dictionary.
/// - Symmetric key (32 random bytes) base64-encoded in `UserDefaults` under
///   `SecretStore.keyDefaultsKey`. The key alone or the ciphertext alone
///   is useless — both are required to recover any secret.
///
/// macOS Keychain is explicitly forbidden by AGENTS.md, so this class uses
/// file storage for both iOS and macOS. The file is created with
/// `NSFileProtectionComplete` (iOS) and chmod 0600 (macOS) to prevent
/// plaintext exfiltration via app backups or shared sandbox snapshots.
final class SecretStore {
    static let shared = SecretStore()

    private enum Const {
        static let keyDefaultsKey = "secretstore.key.v1"
        static let directoryName = "Kelpie"
        static let fileName = "secrets.enc"
    }

    private let fileURL: URL
    private let key: SymmetricKey
    private let queue = DispatchQueue(label: "com.kelpie.secretstore", qos: .userInitiated)
    private var cache: [String: String]

    private init() {
        fileURL = Self.resolveFileURL()
        key = Self.loadOrCreateKey()
        cache = Self.loadCache(from: fileURL, key: key)
    }

    func get(_ name: String) -> String? {
        queue.sync { cache[name] }
    }

    func set(_ name: String, value: String) {
        queue.sync {
            cache[name] = value
            persistLocked()
        }
    }

    func remove(_ name: String) {
        queue.sync {
            cache.removeValue(forKey: name)
            persistLocked()
        }
    }

    // MARK: - Persistence

    private func persistLocked() {
        do {
            let json = try JSONSerialization.data(withJSONObject: cache, options: [.sortedKeys])
            let sealed = try AES.GCM.seal(json, using: key)
            guard let combined = sealed.combined else {
                NSLog("SecretStore: failed to combine sealed box")
                return
            }
            try ensureDirectoryExists()
            try combined.write(to: fileURL, options: [.atomic, .completeFileProtection])
            applyFilePermissions()
        } catch {
            NSLog("SecretStore: persist failed: \(error.localizedDescription)")
        }
    }

    private func ensureDirectoryExists() throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    private func applyFilePermissions() {
        #if os(macOS)
        try? FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: Int16(0o600))],
            ofItemAtPath: fileURL.path
        )
        #endif
    }

    // MARK: - Setup

    private static func resolveFileURL() -> URL {
        let fileManager = FileManager.default
        let base: URL
        if let appSupport = try? fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ) {
            base = appSupport
        } else {
            base = fileManager.temporaryDirectory
        }
        return base
            .appendingPathComponent(Const.directoryName, isDirectory: true)
            .appendingPathComponent(Const.fileName, isDirectory: false)
    }

    private static func loadOrCreateKey() -> SymmetricKey {
        let defaults = UserDefaults.standard
        if let encoded = defaults.string(forKey: Const.keyDefaultsKey),
           let raw = Data(base64Encoded: encoded), raw.count == 32 {
            return SymmetricKey(data: raw)
        }
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        let data: Data
        if status == errSecSuccess {
            data = Data(bytes)
        } else {
            // Fallback — should never trigger on Apple platforms, but never crash a launch.
            data = SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) }
        }
        defaults.set(data.base64EncodedString(), forKey: Const.keyDefaultsKey)
        return SymmetricKey(data: data)
    }

    private static func loadCache(from url: URL, key: SymmetricKey) -> [String: String] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [:] }
        do {
            let blob = try Data(contentsOf: url)
            let sealed = try AES.GCM.SealedBox(combined: blob)
            let plaintext = try AES.GCM.open(sealed, using: key)
            guard let decoded = try JSONSerialization.jsonObject(with: plaintext) as? [String: String] else {
                NSLog("SecretStore: ciphertext decoded to unexpected shape — discarding")
                return [:]
            }
            return decoded
        } catch {
            NSLog("SecretStore: load failed (\(error.localizedDescription)) — starting empty")
            return [:]
        }
    }
}
