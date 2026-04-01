import Foundation

/// Manages a Firefox subprocess with the Remote Debugging Protocol enabled.
/// Finds Firefox.app at standard macOS install paths and spawns it with a
/// dedicated profile so it does not interfere with the user's own Firefox.
@MainActor
final class GeckoProcessManager {
    private(set) var debugPort: Int = 0
    private var process: Process?
    private var profileDir: URL?

    /// System Firefox paths checked as a developer fallback when the bundled
    /// runtime is absent (e.g. before running `make gecko-runtime`).
    static let systemFirefoxPaths: [String] = [
        "/Applications/Firefox.app/Contents/MacOS/firefox",
        "/Applications/Firefox Developer Edition.app/Contents/MacOS/firefox",
        (NSHomeDirectory() as NSString).appendingPathComponent(
            "Applications/Firefox.app/Contents/MacOS/firefox"
        ),
    ]

    enum GeckoError: Error {
        case firefoxNotFound
        case portUnavailable
        case startupTimeout
    }

    /// Path to the Firefox binary bundled inside Mollotov.app.
    /// Returns nil if `make gecko-runtime` has not been run.
    static func bundledFirefoxPath() -> String? {
        guard let executableURL = Bundle.main.executableURL else { return nil }
        let path = executableURL
            .deletingLastPathComponent()          // .../MacOS/Mollotov → .../MacOS
            .deletingLastPathComponent()          // .../MacOS → .../Contents
            .appendingPathComponent("Frameworks/MollotovGeckoHelper.app/Contents/MacOS/firefox")
            .path
        return FileManager.default.isExecutableFile(atPath: path) ? path : nil
    }

    /// Returns the Firefox binary to use: bundled runtime first, system Firefox as fallback.
    static func locateFirefox() -> String? {
        if let bundled = bundledFirefoxPath() { return bundled }
        return systemFirefoxPaths.first { FileManager.default.fileExists(atPath: $0) }
    }

    func start() async throws {
        guard let execPath = Self.locateFirefox() else {
            throw GeckoError.firefoxNotFound
        }

        let port = Self.findFreePort()
        guard port > 0 else { throw GeckoError.portUnavailable }
        debugPort = port

        let tempProfile = FileManager.default.temporaryDirectory
            .appendingPathComponent("com.mollotov.gecko-profile-\(port)")
        try? FileManager.default.createDirectory(at: tempProfile, withIntermediateDirectories: true)
        writeProfilePrefs(to: tempProfile)
        profileDir = tempProfile

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: execPath)
        proc.arguments = [
            "--remote-debugging-port", "\(port)",
            "--no-remote",
            "--profile", tempProfile.path,
            "--headless",
            "about:blank",
        ]
        let logPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("mollotov-gecko-\(port).log").path
        FileManager.default.createFile(atPath: logPath, contents: nil)
        let logHandle = FileHandle(forWritingAtPath: logPath)
        proc.standardOutput = logHandle ?? FileHandle.nullDevice
        proc.standardError = logHandle ?? FileHandle.nullDevice
        NSLog("[GeckoProcessManager] Firefox log: %@", logPath)
        try proc.run()
        process = proc
        NSLog("[GeckoProcessManager] Firefox PID=%d port=%d", proc.processIdentifier, port)

        try await waitForEndpoint(port: port)
    }

    func stop() {
        process?.terminate()
        process = nil
        if let dir = profileDir {
            try? FileManager.default.removeItem(at: dir)
            profileDir = nil
        }
        debugPort = 0
    }

    var isRunning: Bool { process?.isRunning == true }

    private func writeProfilePrefs(to profileURL: URL) {
        let userJS = """
        user_pref("app.update.auto", false);
        user_pref("app.update.enabled", false);
        user_pref("browser.shell.checkDefaultBrowser", false);
        user_pref("browser.startup.firstrunSkipsHomepage", true);
        user_pref("browser.startup.homepage_override.mstone", "ignore");
        user_pref("datareporting.healthreport.uploadEnabled", false);
        user_pref("datareporting.policy.dataSubmissionEnabled", false);
        user_pref("toolkit.telemetry.enabled", false);
        user_pref("toolkit.telemetry.unified", false);
        """
        try? userJS.write(
            to: profileURL.appendingPathComponent("user.js"),
            atomically: true, encoding: .utf8
        )
    }

    private func waitForEndpoint(port: Int, retries: Int = 40) async throws {
        let url = URL(string: "http://127.0.0.1:\(port)/json/version")!
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 1
        cfg.timeoutIntervalForResource = 1
        let sess = URLSession(configuration: cfg)
        for i in 0..<retries {
            try? await Task.sleep(nanoseconds: 250_000_000)
            if let _ = try? await sess.data(from: url) {
                NSLog("[GeckoProcessManager] endpoint ready after %d polls (port %d)", i + 1, port)
                return
            }
        }
        NSLog("[GeckoProcessManager] endpoint not ready after %d polls (port %d)", retries, port)
        throw GeckoError.startupTimeout
    }

    private static func findFreePort() -> Int {
        let sock = socket(AF_INET6, SOCK_STREAM, 0)
        guard sock >= 0 else { return 0 }
        defer { close(sock) }
        var addr = sockaddr_in6()
        addr.sin6_family = sa_family_t(AF_INET6)
        addr.sin6_port = 0
        addr.sin6_addr = in6addr_any
        addr.sin6_len = UInt8(MemoryLayout<sockaddr_in6>.size)
        var result = withUnsafeMutablePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(sock, $0, socklen_t(MemoryLayout<sockaddr_in6>.size))
            }
        }
        guard result == 0 else { return 0 }
        var len = socklen_t(MemoryLayout<sockaddr_in6>.size)
        result = withUnsafeMutablePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                getsockname(sock, $0, &len)
            }
        }
        guard result == 0 else { return 0 }
        return Int(addr.sin6_port.bigEndian)
    }
}
