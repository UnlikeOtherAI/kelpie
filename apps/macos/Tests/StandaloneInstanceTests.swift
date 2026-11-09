import XCTest
import Darwin

final class StandaloneInstanceTests: XCTestCase {
    func testOwnershipSurvivesRejectedLaunchAndReleasesOnExit() throws {
        var first: StandaloneInstance? = try StandaloneInstance(port: 0)
        let port = try XCTUnwrap(first).port
        XCTAssertThrowsError(try StandaloneInstance(port: port)) { error in
            XCTAssertEqual((error as? POSIXError)?.code, .EADDRINUSE)
        }
        XCTAssertThrowsError(try StandaloneInstance(port: port))
        first = nil
        let recovered = try StandaloneInstance(port: port)
        XCTAssertEqual(recovered.port, port)
    }

    func testOwnershipDoesNotOccupyHTTPPort() throws {
        let instance = try StandaloneInstance(port: 0)
        let server = socket(AF_INET, SOCK_STREAM, 0)
        XCTAssertGreaterThanOrEqual(server, 0)
        defer { close(server) }
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = instance.port.bigEndian
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        let result = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(server, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        XCTAssertEqual(result, 0)
        withExtendedLifetime(instance) {}
    }
}
