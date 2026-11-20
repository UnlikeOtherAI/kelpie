import AVFoundation
import Foundation

/// Apple authorizes Kelpie. Kelpie remembers the specific website that the user enabled.
@MainActor
enum MacMicrophonePermission {
    private static let defaultsKey = "microphoneAllowedOrigins"
    private static var systemRequestPending = false

    static func origin(for url: URL?) -> String? {
        guard let url, let scheme = url.scheme?.lowercased(), let host = url.host?.lowercased() else { return nil }
        return origin(scheme: scheme, host: host, port: url.port)
    }

    static func origin(scheme: String, host: String, port: Int?) -> String? {
        let host = host == "::1" ? "[::1]" : host
        let loopback = host == "localhost" || host.hasSuffix(".localhost") || host == "127.0.0.1" || host == "[::1]"
        guard !host.isEmpty, scheme == "https" || (scheme == "http" && loopback) else { return nil }
        guard let port, port != 0, port != (scheme == "https" ? 443 : 80) else { return "\(scheme)://\(host)" }
        return "\(scheme)://\(host):\(port)"
    }

    static func isAllowed(_ origin: String) -> Bool {
        KelpieStorage.defaults.stringArray(forKey: defaultsKey)?.contains(origin) == true
    }

    static func setAllowed(_ allowed: Bool, for origin: String) {
        var origins = Set(KelpieStorage.defaults.stringArray(forKey: defaultsKey) ?? [])
        if allowed { origins.insert(origin) } else { origins.remove(origin) }
        KelpieStorage.defaults.set(origins.sorted(), forKey: defaultsKey)
    }

    static func request(
        _ origin: String,
        stillCurrent: @escaping @MainActor () -> Bool,
        completion: @escaping @MainActor (Bool) -> Void
    ) {
        let usage = Bundle.main.object(forInfoDictionaryKey: "NSMicrophoneUsageDescription") as? String
        guard usage?.isEmpty == false, stillCurrent() else {
            completion(false)
            return
        }
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            completion(isAllowed(origin))
        case .notDetermined:
            guard !systemRequestPending else { completion(false); return }
            systemRequestPending = true
            Task { @MainActor in
                let granted = await AVCaptureDevice.requestAccess(for: .audio)
                systemRequestPending = false
                let allow = granted && stillCurrent()
                if allow { setAllowed(true, for: origin) }
                completion(allow)
            }
        default:
            completion(false)
        }
    }
}
