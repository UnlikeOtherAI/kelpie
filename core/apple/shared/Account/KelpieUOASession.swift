import Combine
import Foundation

/// An authenticated UOA request supplied by the containing app. No refresh token is copied.
@MainActor
public final class KelpieUOASession: ObservableObject {
    public struct Response {
        public let data: Data
        public let version: String?

        public init(data: Data, version: String? = nil) {
            self.data = data
            self.version = version
        }
    }

    public typealias Request = (String, String, Data?, String?) async throws -> Response
    public typealias SettingsSocket = (String, String) async throws -> URLSessionWebSocketTask

    @Published public private(set) var subject: String?
    let request: Request
    let settingsSocket: SettingsSocket
    let signIn: () -> Void
    let signOut: () -> Void

    public init(
        subject: String?,
        request: @escaping Request,
        settingsSocket: @escaping SettingsSocket,
        signIn: @escaping () -> Void,
        signOut: @escaping () -> Void
    ) {
        self.subject = subject
        self.request = request
        self.settingsSocket = settingsSocket
        self.signIn = signIn
        self.signOut = signOut
    }

    /// Call on sign-out, revocation and account replacement, including a new session for the same subject.
    public func update(subject: String?) { self.subject = subject }
}
