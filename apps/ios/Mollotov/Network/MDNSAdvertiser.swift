import Foundation
import Network

/// Advertises the Mollotov service via mDNS using Network.framework.
final class MDNSAdvertiser: @unchecked Sendable {
    private var listener: NWListener?
    private let serviceType = "_mollotov._tcp"
    let txtRecord: [String: String]

    init(txtRecord: [String: String]) {
        self.txtRecord = txtRecord
    }

    func start() {
        do {
            let params = NWParameters()
            params.includePeerToPeer = true
            listener = try NWListener(using: params)
        } catch {
            print("[mDNS] Failed to create listener: \(error)")
            return
        }

        let txt = NWTXTRecord(txtRecord)
        listener?.service = NWListener.Service(
            name: txtRecord["name"] ?? "Mollotov",
            type: serviceType,
            txtRecord: txt
        )

        listener?.serviceRegistrationUpdateHandler = { change in
            switch change {
            case .add(let endpoint):
                print("[mDNS] Advertising: \(endpoint)")
            case .remove(let endpoint):
                print("[mDNS] Removed: \(endpoint)")
            @unknown default:
                break
            }
        }

        listener?.stateUpdateHandler = { state in
            switch state {
            case .ready:
                print("[mDNS] Service advertised as \(self.serviceType)")
            case .failed(let error):
                print("[mDNS] Advertisement failed: \(error)")
            default:
                break
            }
        }

        // We don't actually need to accept connections on this listener.
        // It exists solely for mDNS advertisement.
        listener?.newConnectionHandler = { connection in
            connection.cancel()
        }

        listener?.start(queue: .global(qos: .utility))
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }
}
