import Foundation
import Darwin

/// One loopback UDP reservation shared by all copies, users and sandbox modes.
/// HTTP uses TCP, so this does not occupy the browser's HTTP port. Process exit
/// releases ownership without a persistent file or crash-recovery cleanup.
final class StandaloneInstance {
    private let descriptor: Int32
    let port: UInt16

    init(port: UInt16 = 8420) throws {
        let handle = socket(AF_INET, SOCK_DGRAM, 0)
        guard handle >= 0 else { throw Self.closeAfterError(handle) }
        guard fcntl(handle, F_SETFD, FD_CLOEXEC) == 0 else { throw Self.closeAfterError(handle) }
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = port.bigEndian
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(handle, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bound == 0 else { throw Self.closeAfterError(handle) }
        var size = socklen_t(MemoryLayout<sockaddr_in>.size)
        let inspected = withUnsafeMutablePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(handle, $0, &size) }
        }
        guard inspected == 0 else { throw Self.closeAfterError(handle) }
        descriptor = handle
        self.port = UInt16(bigEndian: address.sin_port)
    }

    deinit { close(descriptor) }

    private static func closeAfterError(_ descriptor: Int32) -> POSIXError {
        let code = POSIXErrorCode(rawValue: errno) ?? .EIO
        if descriptor >= 0 { close(descriptor) }
        return POSIXError(code)
    }
}
