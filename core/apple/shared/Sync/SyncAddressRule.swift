import Darwin
import Foundation
import Network

/// Which peer addresses cookie sync talks to, in both directions: loopback, IPv4/IPv6
/// link-local, or an address inside the directly connected subnet of an eligible
/// interface. Eligible interfaces are the physical Wi-Fi and Ethernet ports (`en*` on
/// Apple platforms) that are up, running, not loopback and not point-to-point. VPN
/// (`utun`, `ipsec`), PPP, cellular (`pdp_ip`), AWDL and bridge interfaces never qualify.
struct SyncAddressRule: Sendable {
    struct Interface: Equatable, Sendable {
        let name: String
        let address: [UInt8]
        let netmask: [UInt8]
    }

    let interfaces: @Sendable () -> [Interface]

    static let system = Self(interfaces: eligibleInterfaces)

    func allows(_ endpoint: NWEndpoint?) -> Bool {
        guard case .hostPort(let host, _) = endpoint else { return false }
        return allows(host)
    }

    func allows(_ host: NWEndpoint.Host) -> Bool {
        switch host {
        case .ipv4(let address):
            return allows(ipv4: address)
        case .ipv6(let address):
            if let mapped = address.asIPv4 { return allows(ipv4: mapped) }
            if address.isLoopback { return true }
            if address.isLinkLocal { return address.interface.map { Self.isEligible(name: $0.name) } ?? true }
            return inConnectedSubnet([UInt8](address.rawValue))
        default:
            return false
        }
    }

    static func isEligible(name: String) -> Bool { name.hasPrefix("en") }

    /// `IPv4Address.isLoopback` covers only 127.0.0.1; the whole of 127/8 is loopback.
    private func allows(ipv4 address: IPv4Address) -> Bool {
        let bytes = [UInt8](address.rawValue)
        return bytes.first == 127 || address.isLinkLocal || inConnectedSubnet(bytes)
    }

    private func inConnectedSubnet(_ bytes: [UInt8]) -> Bool {
        interfaces().contains { interface in
            guard interface.address.count == bytes.count, interface.netmask.count == bytes.count,
                  interface.netmask.contains(where: { $0 != 0 }) else { return false }
            return bytes.indices.allSatisfy { (bytes[$0] & interface.netmask[$0]) == (interface.address[$0] & interface.netmask[$0]) }
        }
    }

    /// Up, running, physical Wi-Fi/Ethernet addresses with their netmasks.
    @Sendable
    static func eligibleInterfaces() -> [Interface] {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else { return [] }
        defer { freeifaddrs(head) }
        var result: [Interface] = []
        for entry in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let flags = Int32(entry.pointee.ifa_flags)
            let required = IFF_UP | IFF_RUNNING
            guard flags & required == required, flags & (IFF_LOOPBACK | IFF_POINTOPOINT) == 0,
                  let address = entry.pointee.ifa_addr, let netmask = entry.pointee.ifa_netmask else { continue }
            let name = String(cString: entry.pointee.ifa_name)
            // BSD netmask sockaddrs often carry no family; read them as the address's family.
            let family = Int32(address.pointee.sa_family)
            guard isEligible(name: name), let bytes = addressBytes(address, family: family),
                  let mask = addressBytes(netmask, family: family) else { continue }
            result.append(Interface(name: name, address: bytes, netmask: mask))
        }
        return result
    }

    private static func addressBytes(_ socket: UnsafeMutablePointer<sockaddr>, family: Int32) -> [UInt8]? {
        switch family {
        case AF_INET:
            return socket.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { pointer in
                withUnsafeBytes(of: pointer.pointee.sin_addr) { [UInt8]($0) }
            }
        case AF_INET6:
            return socket.withMemoryRebound(to: sockaddr_in6.self, capacity: 1) { pointer in
                withUnsafeBytes(of: pointer.pointee.sin6_addr) { [UInt8]($0) }
            }
        default:
            return nil
        }
    }
}
