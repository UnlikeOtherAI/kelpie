import SwiftUI
import Foundation

// This app is a separate, non-shipping target. It never opens the browser,
// touches Kelpie's profile or runs an installer. Fixtures cannot enter real apps.
private final class VerificationFeed: URLProtocol, @unchecked Sendable {
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
            let feed: [[String: Any]] = [["draft": false, "prerelease": false,
                "body": "<!-- kelpie-update: \(String(decoding: metadata, as: UTF8.self)) -->"]]
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
        return AppUpdates(session: session, installed: "0.2.1", performUpdate: { [weak self] item in
            self?.result = "Update \(item.version) selected. No software was changed."
        })
    }()
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
            .modifier(AppUpdatePresentation(updates: session.updates))
        }
    }
}
