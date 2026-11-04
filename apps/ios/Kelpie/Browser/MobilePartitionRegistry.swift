import Foundation
import CoreFoundation
import WebKit

/// Website identity is shared by default. Named stores never fall back to it.
@MainActor
final class MobilePartitionRegistry {
    static let shared = MobilePartitionRegistry()
    private let defaults: UserDefaults
    private let key = "mobilePartitionIdentifiers"
    private var map: PartitionMap
    private var stores: [String: WKWebsiteDataStore] = [:]
    private var deleting: Set<String> = []

    struct Failure: Error {
        let code: String
        let message: String
        var response: [String: Any] { errorResponse(code: code, message: message) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        map = PartitionMap.decode(defaults.dictionary(forKey: key) as? [String: String] ?? [:]).map
    }

    static func validate(_ body: [String: Any]) throws -> (partition: String?, name: String?) {
        if let raw = body["partition"], !(raw is String) {
            throw Failure(code: "INVALID_PARTITION", message: "partition must be a string")
        }
        if let raw = body["persistent"], (raw as? NSNumber).map({ CFGetTypeID($0) != CFBooleanGetTypeID() }) ?? true {
            throw Failure(code: "INVALID_PARAM", message: "persistent must be a boolean")
        }
        if let raw = body["name"], !(raw is String) {
            throw Failure(code: "INVALID_PARAM", message: "name must be a string")
        }
        let name = body["name"] as? String
        if let name, name.utf16.count > PartitionValidator.maxNameLength {
            throw Failure(code: "INVALID_PARAM", message: "name must be at most 200 characters")
        }
        let id = body["partition"] as? String
        if let id {
            if let failure = PartitionValidator.validate(id) {
                throw Failure(code: "INVALID_PARTITION", message: failure.message)
            }
            if body["persistent"] as? Bool == false {
                throw Failure(code: "PARTITION_UNSUPPORTED", message: "Mobile partitions require persistent:true")
            }
        }
        return (id, name)
    }

    func resolve(_ id: String, restoring: Bool = false) throws -> WKWebsiteDataStore {
        if let failure = PartitionValidator.validate(id) {
            throw Failure(code: "INVALID_PARTITION", message: failure.message)
        }
        guard #available(iOS 17.0, *) else {
            throw Failure(code: "PARTITION_UNSUPPORTED", message: "Named partitions require iOS 17 or later")
        }
        guard !deleting.contains(id) else {
            throw Failure(code: "PARTITION_DELETING", message: "Partition deletion is in progress")
        }
        if let store = stores[id] { return store }
        guard !restoring || map.identifier(for: id) != nil else {
            throw Failure(code: "INVALID_PARTITION", message: "Saved partition has no website store mapping")
        }
        let identifier = map.makeIdentifier(for: id)
        defaults.set(map.encoded(), forKey: key)
        let store = WKWebsiteDataStore(forIdentifier: identifier)
        stores[id] = store
        return store
    }

    func listing(tabs: [BrowserTab]) -> [[String: Any]] {
        map.identifiers.keys.sorted().map { id in
            ["id": id, "persistent": true, "tabCount": tabs.filter { $0.partition == id }.count]
        }
    }

    func delete(_ id: String, tabStore: TabStore) async -> [String: Any] {
        guard #available(iOS 17.0, *) else {
            return errorResponse(code: "PARTITION_UNSUPPORTED", message: "Named partitions require iOS 17 or later")
        }
        guard !deleting.contains(id) else {
            return errorResponse(code: "PARTITION_DELETING", message: "Partition deletion is in progress")
        }
        guard let identifier = map.identifier(for: id) else {
            return successResponse(["deleted": id, "existed": false, "tabsClosed": 0])
        }
        deleting.insert(id)
        defer { deleting.remove(id) }
        let ids = tabStore.tabs.filter { $0.partition == id }.map(\.id)
        for tabID in ids { tabStore.closeBrowserTab(id: tabID) }
        stores.removeValue(forKey: id)
        let error: Error? = await withCheckedContinuation { continuation in
            WKWebsiteDataStore.remove(forIdentifier: identifier) { continuation.resume(returning: $0) }
        }
        if let error {
            return errorResponse(code: "PARTITION_IN_USE", message: error.localizedDescription)
        }
        map.remove(id)
        defaults.set(map.encoded(), forKey: key)
        return successResponse(["deleted": id, "existed": true, "tabsClosed": ids.count])
    }
}
