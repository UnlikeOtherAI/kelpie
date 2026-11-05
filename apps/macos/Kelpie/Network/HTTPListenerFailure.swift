import Network

enum HTTPListenerFailure {
    static func isRecoverableBonjour(_ error: NWError) -> Bool {
        guard case .dns(let code) = error else { return false }
        return code == -65563 // kDNSServiceErr_ServiceNotRunning
    }

    #if DEBUG
    static func facts(_ error: NWError) -> (domain: String, code: Int) {
        switch error {
        case .posix(let code): return ("posix", Int(code.rawValue))
        case .dns(let code): return ("dns", Int(code))
        case .tls(let code): return ("tls", Int(code))
        case .wifiAware: return ("other", 0)
        @unknown default: return ("other", 0)
        }
    }
    #endif

}
