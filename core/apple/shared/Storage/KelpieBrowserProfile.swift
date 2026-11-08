import CryptoKit
import Foundation

/// Selects browser-owned local data before creating an embedded runtime.
/// Only the containing app knows which current UOA subject owns the presentation.
@MainActor
public enum KelpieBrowserProfile {
    public enum Failure: Error { case invalidOwner, runtimeActive, transitionInProgress, unsupported }
    private static var runtime: UUID?
    private static var changing = false

    public static func activate(issuer: String, subject: String) async throws {
        guard !KelpieStorage.standalone else { throw Failure.unsupported }
        #if os(macOS) && !KELPIE_WEBKIT_ONLY
        // CEF's process-level data directory cannot be replaced after bootstrap.
        throw Failure.unsupported
        #else
        guard let url = URL(string: issuer), url.scheme == "https", url.host != nil,
              url.user == nil, url.password == nil, url.query == nil, url.fragment == nil,
              url.path.isEmpty, !subject.isEmpty, subject.utf8.count <= 256 else { throw Failure.invalidOwner }
        let owner = try JSONEncoder().encode([issuer, subject])
        let profile = SHA256.hash(data: owner).map { String(format: "%02x", $0) }.joined()
        guard !changing else { throw Failure.transitionInProgress }
        if KelpieStorage.profileID == profile { return }
        guard runtime == nil else { throw Failure.runtimeActive }
        changing = true
        defer { changing = false }
        UOAAccount.shared.retireProfile()
        NetworkTrafficStore.shared.flush()
        AIState.shared.retireProfile()
        let endpoints = OpenAIEndpointService.shared
        #if os(macOS)
        AIEndpointState.shared.retireProfile()
        InferenceEngine.shared.cancel()
        await InferenceEngine.shared.unload()
        #else
        OpenAIEndpointMonitor.shared.stop()
        LocalInference.shared.cancel()
        _ = await LocalInference.shared.execute("unload")
        #endif
        await endpoints.retireProfile()
        KelpieStorage.select(profile: profile)
        #endif
    }

    static func acquire(_ id: UUID) {
        precondition(runtime == nil && !changing, "Close the existing browser runtime before creating another")
        runtime = id
    }

    static func release(_ id: UUID) {
        if runtime == id { runtime = nil }
    }
}
