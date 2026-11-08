#if DEBUG
import AppReveal
import Darwin

enum KelpieDiagnostics {
    @MainActor
    static func start() {
        guard canBind(port: 8421) else { return }
        AppReveal.start(port: 8421)
    }

    private static func canBind(port: UInt16) -> Bool {
        let descriptor = socket(AF_INET6, SOCK_STREAM, 0)
        guard descriptor >= 0 else { return false }
        defer { close(descriptor) }
        var reuse: Int32 = 1
        let length = socklen_t(MemoryLayout<Int32>.size)
        _ = setsockopt(descriptor, SOL_SOCKET, SO_REUSEADDR, &reuse, length)
        var address = sockaddr_in6()
        address.sin6_len = UInt8(MemoryLayout<sockaddr_in6>.size)
        address.sin6_family = sa_family_t(AF_INET6)
        address.sin6_port = port.bigEndian
        address.sin6_addr = in6addr_any
        return withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in6>.size)) == 0
            }
        }
    }
}
#endif
