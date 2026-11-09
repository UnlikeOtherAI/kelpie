import SwiftUI
import Foundation
#if os(macOS)
import AppKit
#endif

// This app is a separate, non-shipping target. It never opens the browser,
// touches Kelpie's profile or runs an installer. Fixtures cannot enter real apps.
private class VerificationFeed: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let arguments = ProcessInfo.processInfo.arguments
        let index = arguments.firstIndex(of: "--version")
        let requested = index.flatMap { arguments.indices.contains($0 + 1) ? arguments[$0 + 1] : nil } ?? "0.2.2"
        let version = AppRelease.version(requested) == nil ? "0.2.2" : requested
        let target = AppUpdates.platformTarget
        let item = ["target": target, "version": version,
                    "url": target == "ios" ? "https://apps.apple.com/app/id123456789" :
                        "https://github.com/UnlikeOtherAI/kelpie/releases/download/verification/unused.zip",
                    "sha256": String(repeating: "a", count: 64)]
        do {
            let metadata = try JSONSerialization.data(withJSONObject: item)
            guard let text = String(bytes: metadata, encoding: .utf8) else { return }
            let feed: [[String: Any]] = [[
                "draft": false,
                "prerelease": false,
                "body": "<!-- kelpie-update: \(text) -->"
            ]]
            guard let url = request.url, let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil) else { return }
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: try JSONSerialization.data(withJSONObject: feed))
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}

@MainActor
private final class VerificationSession: ObservableObject {
    @Published var result = "No update selected."
    lazy var updates: AppUpdates = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [VerificationFeed.self]
        let session = URLSession(configuration: configuration)
        let arguments = ProcessInfo.processInfo.arguments
        let index = arguments.firstIndex(of: "--run-id")
        let requested = index.flatMap { arguments.indices.contains($0 + 1) ? arguments[$0 + 1] : nil }
        let run = requested.flatMap(UUID.init(uuidString:))?.uuidString ?? "manual"
        let defaults = UserDefaults(suiteName: "com.unlikeotherai.kelpie.update-verification.\(run)") ?? .standard
        return AppUpdates(defaults: defaults, session: session, installed: "0.2.1", performUpdate: { [weak self] item in
            self?.result = "Update \(item.version) selected. No software was changed."
            self?.updates.installing = true
        })
    }()

    // Export only this fixture's rendered views. This needs no permission to
    // record the person's desktop and cannot capture another application's UI.
    func captureViews() async {
        #if os(macOS)
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: "--screenshots"), args.indices.contains(index + 1),
              args[index + 1].hasPrefix("/") else { return }
        try? await Task.sleep(nanoseconds: 500_000_000)
        let directory = URL(fileURLWithPath: args[index + 1], isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            for window in NSApp.windows where window.isVisible {
                let name = window.sheetParent != nil ? "mac-update-prompt.png" :
                    (updates.installing ? "mac-update-progress.png" : nil)
                guard let name, let view = window.contentView,
                      let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { continue }
                view.layoutSubtreeIfNeeded()
                view.cacheDisplay(in: view.bounds, to: bitmap)
                guard let data = bitmap.representation(using: .png, properties: [:]) else { continue }
                try data.write(to: directory.appendingPathComponent(name))
            }
        } catch { result = "Screenshot export failed: \(error.localizedDescription)" }
        #endif
    }
}

@main
private struct UpdateVerificationApp: App {
    @StateObject private var session = VerificationSession()

    var body: some Scene {
        WindowGroup("Kelpie Update Verification") {
            VStack(spacing: 16) {
                Text("UPDATE VERIFICATION").font(.headline)
                Text("This is an isolated test app. Update is simulated.\nYour Kelpie installation and browsing data are untouched.")
                Text(session.result).accessibilityIdentifier("verification-result")
            }
            .padding(32)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .modifier(AppUpdatePresentation(updates: session.updates))
            .task { await session.captureViews() }
            .onChange(of: session.result) { _ in Task { await session.captureViews() } }
        }
    }
}
