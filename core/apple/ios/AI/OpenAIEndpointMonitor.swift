import Network
import UIKit

/// Keeps the active OpenAI-compatible endpoint's health current on iOS:
/// polling starts at launch when an endpoint is selected, and re-checks run
/// immediately when the app becomes active again or the network path changes.
/// The service only ever polls the active endpoint; with none selected these
/// triggers are no-ops.
@MainActor
final class OpenAIEndpointMonitor {
    static let shared = OpenAIEndpointMonitor()

    private let service = OpenAIEndpointService.shared
    private var pathMonitor: NWPathMonitor?
    private var lastPathStatus: NWPath.Status?
    private var becameActiveObserver: NSObjectProtocol?

    private init() {}

    /// Idempotent; safe to call from every scene `onAppear`.
    func start() {
        guard pathMonitor == nil else { return }
        refreshNow()

        becameActiveObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refreshNow() }
        }

        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            let status = path.status
            Task { @MainActor in self?.pathChanged(to: status) }
        }
        monitor.start(queue: DispatchQueue(label: "com.unlikeotherai.kelpie.openai-path"))
        pathMonitor = monitor
    }

    private func pathChanged(to status: NWPath.Status) {
        // The first callback reports the current path, not a change.
        defer { lastPathStatus = status }
        guard lastPathStatus != nil else { return }
        refreshNow()
    }

    private func refreshNow() {
        let service = service
        Task { await service.refreshActiveNow() }
    }
}
