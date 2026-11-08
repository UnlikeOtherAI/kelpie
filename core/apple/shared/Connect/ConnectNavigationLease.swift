import Foundation

/// WebKit navigation object identity proves which document was opened by the reserved mutation.
@MainActor
final class ConnectNavigationLease {
    private let initial: String
    private var issued = false
    private var token: AnyObject?
    private var destination: String?
    private var invalid = false

    init(initial: String) { self.initial = initial }

    func issued(_ navigation: AnyObject?) {
        guard !issued else { invalid = true; return }
        issued = true
        token = navigation
    }

    func started(previous: String, version: String, navigation: AnyObject?) {
        guard issued, !invalid, destination == nil, previous == initial,
              let token, let navigation, token === navigation else { invalid = true; return }
        destination = version
    }

    func allowsRead(version: String, loading: Bool, authorized: Bool) -> Bool {
        issued && !invalid && authorized && !loading && version == (destination ?? (token == nil ? initial : ""))
    }

    func allowsWait(version: String, authorized: Bool) -> Bool {
        issued && !invalid && authorized && (destination == nil || destination == version)
    }
}
