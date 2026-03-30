import Foundation
import WebKit

/// Observable state for the HTTP server and mDNS advertiser.
final class ServerState: ObservableObject {
    @Published var isServerRunning = false
    @Published var isMDNSAdvertising = false
    @Published var ipAddress: String = "0.0.0.0"

    let deviceInfo: DeviceInfo
    let router = Router()
    weak var webView: WKWebView?

    private var httpServer: HTTPServer?
    private var mdnsAdvertiser: MDNSAdvertiser?

    init(port: UInt16 = 8420) {
        self.deviceInfo = DeviceInfo.current(port: Int(port))
        self.ipAddress = Self.getLocalIPAddress()
    }

    func startHTTPServer() {
        router.registerStubs()
        httpServer = HTTPServer(port: UInt16(deviceInfo.port), router: router)
        httpServer?.start()
        DispatchQueue.main.async { self.isServerRunning = true }
    }

    func startMDNS() {
        mdnsAdvertiser = MDNSAdvertiser(txtRecord: deviceInfo.txtRecord)
        mdnsAdvertiser?.start()
        DispatchQueue.main.async { self.isMDNSAdvertising = true }
    }

    func stop() {
        httpServer?.stop()
        mdnsAdvertiser?.stop()
        DispatchQueue.main.async {
            self.isServerRunning = false
            self.isMDNSAdvertising = false
        }
    }

    private static func getLocalIPAddress() -> String {
        var address = "0.0.0.0"
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else { return address }
        defer { freeifaddrs(ifaddr) }

        for ptr in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
            let interface = ptr.pointee
            let addrFamily = interface.ifa_addr.pointee.sa_family
            if addrFamily == UInt8(AF_INET) {
                let name = String(cString: interface.ifa_name)
                if name == "en0" || name == "en1" {
                    var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    getnameinfo(interface.ifa_addr, socklen_t(interface.ifa_addr.pointee.sa_len),
                                &hostname, socklen_t(hostname.count), nil, 0, NI_NUMERICHOST)
                    address = String(cString: hostname)
                    break
                }
            }
        }
        return address
    }
}
