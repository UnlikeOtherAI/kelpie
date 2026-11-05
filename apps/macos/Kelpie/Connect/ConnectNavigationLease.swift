import Foundation

/// WebKit navigation object identity proves which document was opened by the reserved mutation.
@MainActor
final class ConnectNavigationLease {
    private let initial: String
    private var issued = false
    private var token: AnyObject?
    private var destination: String?
    private var invalid = false

    #if DEBUG
    private enum Invalidation: String {
        case duplicateIssue = "duplicate-issue"
        case startBeforeIssue = "start-before-issue"
        case alreadyInvalid = "already-invalid"
        case secondStart = "second-start"
        case previousVersionChanged = "previous-version-changed"
        case missingIssuedToken = "missing-issued-token"
        case missingCallbackToken = "missing-callback-token"
        case unexpectedNavigationToken = "unexpected-navigation-token"
    }
    private var debugInvalidation: Invalidation?

    /// Fixed state labels only. Never include document versions, navigation identities or URLs.
    var debugState: String {
        debugInvalidation?.rawValue ?? (issued ? (destination == nil ? "awaiting-start" : "destination-reserved") : "awaiting-issue")
    }

    private func recordInvalidation(_ reason: Invalidation) {
        guard debugInvalidation == nil else { return }
        debugInvalidation = reason
        print("[WorkflowNavigationLease] invalid=" + reason.rawValue)
    }

    private func invalidStartReason(previous: String, navigation: AnyObject?) -> Invalidation {
        if !issued { return .startBeforeIssue }
        if invalid { return .alreadyInvalid }
        if destination != nil { return .secondStart }
        if previous != initial { return .previousVersionChanged }
        if token == nil { return .missingIssuedToken }
        if navigation == nil { return .missingCallbackToken }
        return .unexpectedNavigationToken
    }
    #endif

    init(initial: String) { self.initial = initial }

    func issued(_ navigation: AnyObject?) {
        guard !issued else {
            #if DEBUG
            recordInvalidation(.duplicateIssue)
            #endif
            invalid = true
            return
        }
        issued = true
        token = navigation
    }

    func started(previous: String, version: String, navigation: AnyObject?) {
        guard issued, !invalid, destination == nil, previous == initial,
              let token, let navigation, token === navigation else {
            #if DEBUG
            recordInvalidation(invalidStartReason(previous: previous, navigation: navigation))
            #endif
            invalid = true
            return
        }
        destination = version
    }

    func allowsRead(version: String, loading: Bool, authorized: Bool) -> Bool {
        issued && !invalid && authorized && !loading && version == (destination ?? (token == nil ? initial : ""))
    }

    func allowsWait(version: String, authorized: Bool) -> Bool {
        issued && !invalid && authorized && (destination == nil || destination == version)
    }
}
