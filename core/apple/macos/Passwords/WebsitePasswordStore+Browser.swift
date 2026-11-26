import Foundation

extension WebsitePasswordStore {
    init() {
        let hostID = Bundle.main.bundleIdentifier ?? "kelpie-host"
        if KelpieStorage.standalone {
            self = .sharedWithProvider(hostID: hostID)
        } else {
            self.init(service: hostID + ".website-passwords." + KelpieStorage.profileID)
        }
    }
}
