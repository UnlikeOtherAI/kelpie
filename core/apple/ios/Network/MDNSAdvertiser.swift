import Foundation
import Network

/// Publishes the Kelpie Bonjour service on the live `HTTPServer` listener.
///
/// We deliberately avoid creating a second `NWListener` here: a standalone
/// listener would bind an ephemeral port, and Network.framework advertises
/// whatever port the listener actually owns — not the value stuffed into the
/// TXT record. Attaching the `NWListener.Service` to `HTTPServer`'s listener
/// guarantees the advertised port matches the port the API server is serving
/// on.
final class MDNSAdvertiser: @unchecked Sendable {
    private let serviceType = "_kelpie._tcp"
    private weak var httpServer: HTTPServer?
    let txtRecord: [String: String]
    var onAdvertisingChange: ((Bool) -> Void)?
    private(set) var isRunning = false

    init(txtRecord: [String: String], httpServer: HTTPServer) {
        self.txtRecord = txtRecord
        self.httpServer = httpServer
    }

    func start() {
        guard let httpServer else {
            print("[mDNS] No HTTPServer to attach service to")
            onAdvertisingChange?(false)
            return
        }

        httpServer.serviceRegistrationUpdateHandler = { [weak self] change in
            guard let self else { return }
            switch change {
            case .add(let endpoint):
                self.isRunning = true
                self.onAdvertisingChange?(true)
                print("[mDNS] Advertising: \(endpoint)")
            case .remove(let endpoint):
                self.isRunning = false
                self.onAdvertisingChange?(false)
                print("[mDNS] Removed: \(endpoint)")
            @unknown default:
                break
            }
        }

        let txt = NWTXTRecord(txtRecord)
        let service = NWListener.Service(
            name: txtRecord["name"] ?? "Kelpie",
            type: serviceType,
            txtRecord: txt
        )
        httpServer.attachService(service)
        print("[mDNS] Service requested as \(serviceType) on port \(httpServer.port)")
    }

    func stop() {
        httpServer?.attachService(nil)
        httpServer?.serviceRegistrationUpdateHandler = nil
        isRunning = false
        onAdvertisingChange?(false)
    }
}
