import Foundation
import os

/// How a sync service is hosted: identity shown to peers, where its store lives, and
/// the pieces tests replace.
struct SyncEnvironment {
    var platform: String
    var deviceName: String
    var storeURL: URL
    var timing = SyncTiming.standard
    var rule = SyncAddressRule.system
    var advertise = true
    var clock: @Sendable () -> Int64 = { Int64((Date().timeIntervalSince1970 * 1_000).rounded(.down)) }
    var makeDiscovery: @MainActor (SyncDiscoveryContext) -> SyncDiscovery = { SyncBrowser(context: $0) }
    /// True only for the first store open in this process (`launch:true`).
    var claimLaunch: @MainActor () -> Bool = SyncProcess.claimLaunch

    init(platform: String, deviceName: String, storeURL: URL = SyncStoreLocation.defaultURL) {
        self.platform = platform
        self.deviceName = Self.displayName(deviceName)
        self.storeURL = storeURL
    }

    /// Printable and at most 64 UTF-8 bytes, as `hello` requires.
    static func displayName(_ raw: String) -> String {
        var name = String(String.UnicodeScalarView(raw.unicodeScalars.filter { $0.value >= 0x20 && $0.value != 0x7f }))
        while name.utf8.count > 64 { name.removeLast() }
        return name
    }
}

@MainActor
enum SyncProcess {
    private static var opened = false

    static func claimLaunch() -> Bool {
        defer { opened = true }
        return !opened
    }
}

/// `<app support>/Kelpie/sync/cookie-sync.json`, private to the user, excluded from
/// backups and, on iOS, encrypted while the device is locked. core-sync writes the file
/// atomically itself; it holds no cookie values.
enum SyncStoreLocation {
    static var defaultURL: URL {
        KelpieStorage.isolated(FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0])
            .appendingPathComponent("Kelpie/sync/cookie-sync.json")
    }

    static func prepare(_ url: URL) throws {
        var directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try directory.setResourceValues(values)
        #if os(iOS)
        try FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: directory.path)
        #endif
    }
}

/// Sync logs carry codes and counts only: never cookie names, domains, values, tickets,
/// keys or boxes.
enum SyncLog {
    private static let logger = Logger(subsystem: "com.unlikeotherai.kelpie", category: "cookie-sync")

    static func info(_ message: String) { logger.info("\(message, privacy: .public)") }

    static func failure(_ step: String, _ error: Error) {
        logger.error("\(step, privacy: .public) failed: \(SyncFailure.code(of: error), privacy: .public)")
    }
}

/// A protocol-level failure with the code status reports.
struct SyncFailure: Error, Equatable {
    let code: String

    init(_ code: String) { self.code = code }

    /// The documented codes a peer may send back. Anything else — which could be a
    /// reflected ticket or cookie text — becomes `PEER_ERROR` before it reaches a log or
    /// the status.
    private static let peerCodes: Set<String> = [
        "ACCOUNT_MISMATCH", "AUTH_FAILED", "BAD_REQUEST", "CLOCK_SKEW", "DUPLICATE_CONTENT_LENGTH", "FORBIDDEN",
        "HEADERS_TOO_LARGE", "INVALID_BOX", "INVALID_CONTENT_LENGTH", "INVALID_MESSAGE", "LENGTH_REQUIRED",
        "METHOD_NOT_ALLOWED", "NOT_FOUND", "ORIGIN_REJECTED", "PAYLOAD_TOO_LARGE", "PROOF_REJECTED", "RATE_LIMITED",
        "REPLAY", "REPLAYED", "REQUEST_TIMEOUT", "SESSION_EXISTS", "SYNC_SESSION", "TRANSFER_ENCODING", "UNAVAILABLE",
        "UNSUPPORTED_MEDIA_TYPE", "UOA_BUSY", "UOA_UNAVAILABLE"
    ]

    static func peer(_ raw: Any?, status: Int) -> Self {
        guard let text = raw as? String else { return Self("HTTP_\(status)") }
        return Self(peerCodes.contains(text) ? text : "PEER_ERROR")
    }

    static func code(of error: Error) -> String {
        switch error {
        case let failure as Self: return failure.code
        case let failure as SyncNetworkError: return failure.code
        case let failure as SyncStoreBridge.Failure: return failure.code
        case is CancellationError: return "CANCELLED"
        default: return "INTERNAL"
        }
    }
}
