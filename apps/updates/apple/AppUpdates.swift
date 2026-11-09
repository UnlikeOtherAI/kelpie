import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

@MainActor
final class AppUpdates: ObservableObject {
    @Published var offered: AppRelease?
    @Published var errorMessage: String?
    @Published var installing = false
    private var loop: Task<Void, Never>?
    private var dismissed = Set<String>()
    private var candidate: AppRelease?
    private var active = false
    private var checking = false
    private let defaults: UserDefaults
    private let installed: String
    private let target: String
    private let session: URLSession
    private let feedURL: URL
    #if os(macOS)
    private var installer: Process?
    #endif

    init(defaults: UserDefaults = .standard, session: URLSession = .shared,
         installed: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "",
         target: String? = nil, feedURL: URL? = nil) {
        guard let endpoint = feedURL ?? URL(string: "https://api.github.com/repos/UnlikeOtherAI/kelpie/releases?per_page=100") else {
            preconditionFailure("The built-in Kelpie release URL must be valid.")
        }
        self.defaults = defaults
        self.session = session
        self.installed = installed
        self.target = target ?? Self.platformTarget
        self.feedURL = endpoint
    }

    static var platformTarget: String {
        #if os(iOS)
        return "ios"
        #elseif arch(arm64)
        return "macos-arm64"
        #else
        return "macos-x64"
        #endif
    }

    func activate(_ value: Bool) {
        active = value
        if value { presentCandidate() }
        guard loop == nil else { return }
        loop = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let success = await self.check()
                do { try await Task.sleep(nanoseconds: UInt64(success ? 21_600 : 900) * 1_000_000_000) }
                catch { return }
            }
        }
    }

    @discardableResult
    func check() async -> Bool {
        guard !checking else { return true }
        checking = true
        defer { checking = false }
        do {
            #if DEBUG
            if let fixture = ProcessInfo.processInfo.environment["KELPIE_UPDATE_TEST_FEED_JSON"], fixture.utf8.count <= 1_048_576 {
                candidate = AppRelease.newest(in: Data(fixture.utf8), target: target, installed: installed)
                presentCandidate()
                return true
            }
            if let fixture = ProcessInfo.processInfo.environment["KELPIE_UPDATE_TEST_FEED"] {
                let data = try Data(contentsOf: URL(fileURLWithPath: fixture))
                candidate = AppRelease.newest(in: data, target: target, installed: installed)
                presentCandidate()
                return true
            }
            #endif
            var request = URLRequest(url: feedURL, timeoutInterval: 15)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            request.setValue("Kelpie-update-check", forHTTPHeaderField: "User-Agent")
            let (data, response) = try await session.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200, data.count <= 8 * 1_024 * 1_024,
                  (try? JSONSerialization.jsonObject(with: data)) is [Any] else { return false }
            candidate = AppRelease.newest(in: data, target: target, installed: installed)
            presentCandidate()
            return true
        } catch { return false } // Offline checks never interrupt browsing or lose a pending choice.
    }

    private func presentCandidate() {
        guard active, !installing, offered == nil, let item = candidate,
              !dismissed.contains(item.version),
              !(defaults.stringArray(forKey: "updates.skippedVersions") ?? []).contains(item.version) else { return }
        offered = item
        dismissed.insert(item.version)
        #if os(macOS)
        showMacPrompt(item)
        #endif
    }

    func skip(_ item: AppRelease) {
        var versions = Set(defaults.stringArray(forKey: "updates.skippedVersions") ?? [])
        versions.insert(item.version)
        defaults.set(Array(versions), forKey: "updates.skippedVersions")
        offered = nil
    }

    func notNow() { offered = nil }

    func update(_ item: AppRelease) {
        offered = nil
        #if os(macOS)
        installMac(item)
        #else
        UIApplication.shared.open(item.url) { [weak self] opened in
            guard !opened else { return }
            Task { @MainActor in self?.errorMessage = "The update page could not open. Try again after restarting Kelpie." }
        }
        #endif
    }

    #if os(macOS)
    private func showMacPrompt(_ item: AppRelease) {
        guard let window = NSApp.mainWindow ?? NSApp.keyWindow, window.attachedSheet == nil else {
            offered = nil
            dismissed.remove(item.version)
            return
        }
        let alert = NSAlert()
        alert.messageText = "Kelpie \(item.version) is available"
        alert.informativeText = "Update downloads, verifies and installs the new version, then restarts Kelpie. Not now asks again next time you start the app."
        alert.addButton(withTitle: "Update")
        alert.addButton(withTitle: "Skip version")
        alert.addButton(withTitle: "Not now")
        alert.buttons[0].keyEquivalent = ""
        alert.buttons[2].keyEquivalent = "\r"
        alert.beginSheetModal(for: window) { [weak self] choice in
            guard let self else { return }
            if choice == .alertFirstButtonReturn { self.update(item) }
            else if choice == .alertSecondButtonReturn { self.skip(item) }
            else { self.notNow() }
        }
    }

    private func installMac(_ item: AppRelease) {
        guard let script = Bundle.main.url(forResource: "install-macos", withExtension: "sh"), let hash = item.sha256 else {
            errorMessage = "The updater is missing from this Kelpie installation."
            return
        }
        installing = true
        Task {
            do {
                let operation = FileManager.default.temporaryDirectory.appendingPathComponent("kelpie-update-\(UUID().uuidString)")
                try FileManager.default.createDirectory(at: operation, withIntermediateDirectories: true,
                                                       attributes: [.posixPermissions: 0o700])
                let helper = operation.appendingPathComponent("install.sh")
                try FileManager.default.copyItem(at: script, to: helper)
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/bin/bash")
                process.arguments = [helper.path, operation.path, String(ProcessInfo.processInfo.processIdentifier),
                                     item.url.absoluteString, hash, item.version, Bundle.main.bundleURL.path] +
                    Array(ProcessInfo.processInfo.arguments.dropFirst())
                let log = operation.appendingPathComponent("installer.log")
                FileManager.default.createFile(atPath: log.path, contents: nil)
                let output = try FileHandle(forWritingTo: log)
                process.standardOutput = output
                process.standardError = output
                try process.run()
                try output.close()
                installer = process
                var requestedQuit = false
                while process.isRunning {
                    let state = try? String(contentsOf: operation.appendingPathComponent("status"), encoding: .utf8)
                    if state?.trimmingCharacters(in: .whitespacesAndNewlines) == "ready", !requestedQuit {
                        requestedQuit = true
                        NSApp.terminate(nil)
                    }
                    try await Task.sleep(nanoseconds: 300_000_000)
                }
                let message = (try? String(contentsOf: operation.appendingPathComponent("error"), encoding: .utf8)) ??
                    "The update could not be downloaded or verified. Your current installation is unchanged."
                throw NSError(domain: "KelpieUpdate", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
            } catch { errorMessage = error.localizedDescription; installing = false }
        }
    }
    #endif
}

struct AppUpdatePresentation: ViewModifier {
    @ObservedObject var updates: AppUpdates
    @Environment(\.scenePhase) private var phase

    func body(content: Content) -> some View {
        content
            .task { updates.activate(phase == .active) }
            .onChange(of: phase) { updates.activate($0 == .active) }
            #if os(macOS)
            .onReceive(NotificationCenter.default.publisher(for: NSWindow.didEndSheetNotification)) { _ in
                updates.activate(phase == .active)
            }
            #endif
            .alert("Kelpie could not update", isPresented: Binding(
                get: { updates.errorMessage != nil }, set: { if !$0 { updates.errorMessage = nil } }
            )) { Button("OK") { updates.errorMessage = nil } } message: { Text(updates.errorMessage ?? "") }
            .overlay(alignment: .bottom) {
                if updates.installing { Text("Downloading and verifying update… Kelpie will restart when ready.").padding().background(.regularMaterial).padding() }
            }
            #if os(iOS)
            .alert("A new Kelpie version is available", isPresented: Binding(
                get: { updates.offered != nil }, set: { if !$0 { updates.notNow() } }
            ), presenting: updates.offered) { item in
                Button("Update") { updates.update(item) }
                Button("Skip version") { updates.skip(item) }
                Button("Not now", role: .cancel) { updates.notNow() }
            } message: { item in
                Text("Kelpie \(item.version) is available. Not now asks again next time you start the app.")
            }
            #endif
    }
}
