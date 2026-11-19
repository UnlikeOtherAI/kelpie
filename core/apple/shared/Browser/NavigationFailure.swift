import Foundation
import Network

enum NavigationFailure {
    static func message(for error: NSError) -> String {
        let description = error.localizedDescription
        guard error.domain == NSURLErrorDomain,
              let url = error.userInfo[NSURLErrorFailingURLErrorKey] as? URL,
              let host = url.host(percentEncoded: false)?.lowercased(),
              isLoopback(host) else { return description }

        switch error.code {
        case NSURLErrorCannotConnectToHost, NSURLErrorCannotFindHost, NSURLErrorDNSLookupFailed:
            return description + " Loopback addresses refer to the device running Kelpie. "
                + "Check that the server is listening there, or use the server's LAN address if it runs on another machine."
        case NSURLErrorAppTransportSecurityRequiresSecureConnection:
            return description + " This browser blocks insecure HTTP for this loopback URL. Use HTTPS."
        default:
            return description
        }
    }

    private static func isLoopback(_ host: String) -> Bool {
        let bare = host.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        if bare == "localhost" || bare.hasSuffix(".localhost") { return true }
        if let ipv6 = IPv6Address(bare) {
            return ipv6.isLoopback || ipv6.asIPv4?.rawValue.first == 127
        }
        return IPv4Address(bare)?.rawValue.first == 127
    }
}
