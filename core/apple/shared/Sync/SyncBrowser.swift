import Foundation
import Network

/// One advertised sync listener: TXT `v=1`, `id=<replica>`, `h=<account hint>`.
struct SyncAdvert: Equatable {
    let replica: String
    let hint: String
    let name: String
    let endpoint: NWEndpoint
}

/// What a discovery needs from the run that owns it.
struct SyncDiscoveryContext {
    let ownReplica: String
    let rule: SyncAddressRule
    let acceptedHints: @MainActor () -> Set<String>
}

/// Peer discovery for one run. Only adverts with an accepted hint are reported.
@MainActor
protocol SyncDiscovery: AnyObject {
    func start(onChange: @escaping @MainActor ([SyncAdvert]) -> Void)
    func stop()
    /// Re-filters the last results, for example after the UTC date changed.
    func refresh()
    /// The address the advert is reached on, checked against the address rule.
    func resolve(_ advert: SyncAdvert) async -> NWEndpoint?
}

/// Browses `_kelpie-sync._tcp` with Network.framework.
@MainActor
final class SyncBrowser: SyncDiscovery {
    private let context: SyncDiscoveryContext
    private var browser: NWBrowser?
    private var results: Set<NWBrowser.Result> = []
    private var onChange: (@MainActor ([SyncAdvert]) -> Void)?

    init(context: SyncDiscoveryContext) {
        self.context = context
    }

    func start(onChange: @escaping @MainActor ([SyncAdvert]) -> Void) {
        guard browser == nil else { return }
        self.onChange = onChange
        let parameters = NWParameters.tcp
        parameters.prohibitedInterfaceTypes = [.cellular]
        let browser = NWBrowser(for: .bonjourWithTXTRecord(type: SyncListener.serviceType, domain: nil), using: parameters)
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            MainActor.assumeIsolated {
                self?.results = results
                self?.refresh()
            }
        }
        browser.stateUpdateHandler = { [weak self] state in
            guard case .failed = state else { return }
            MainActor.assumeIsolated { self?.restart() }
        }
        self.browser = browser
        browser.start(queue: .main)
    }

    func stop() {
        browser?.cancel()
        browser = nil
        results = []
        onChange = nil
    }

    func refresh() {
        let accepted = context.acceptedHints()
        let adverts = results.compactMap { Self.advert($0) }
            .filter { $0.replica != context.ownReplica && accepted.contains($0.hint) }
        onChange?(adverts)
    }

    func resolve(_ advert: SyncAdvert) async -> NWEndpoint? {
        await SyncHTTPClient.resolve(advert.endpoint, rule: context.rule)
    }

    private func restart() {
        guard let onChange else { return }
        browser?.cancel()
        browser = nil
        results = []
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.browser == nil, self.onChange != nil else { return }
                self.start(onChange: onChange)
            }
        }
    }

    static func advert(_ result: NWBrowser.Result) -> SyncAdvert? {
        guard case .bonjour(let txt) = result.metadata, txt["v"] == "1",
              let replica = txt["id"], Base64URL.decode(replica)?.count == 16,
              let hint = txt["h"], Base64URL.decode(hint)?.count == 8 else { return nil }
        var name = replica
        if case .service(let service, _, _, _) = result.endpoint { name = service }
        return SyncAdvert(replica: replica, hint: hint, name: name, endpoint: result.endpoint)
    }
}
