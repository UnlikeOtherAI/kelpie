import Foundation

/// The ordered tree is shared by UI, HTTP and account sync. Start-page consumers
/// use the leaf projection; account data never overwrites the local collection.
@MainActor
final class BookmarkStore: ObservableObject {
    static let shared = BookmarkStore()
    @Published private(set) var nodes: [Bookmark] = []
    var bookmarks: [Bookmark] { nodes.filter { !$0.isFolder } }
    @Published private(set) var syncError: String?
    @Published private(set) var isSyncing = false
    @Published private(set) var canUndoRemoval = false
    private(set) var generation = UUID()
    private var accountBookmarks: AccountBookmarks?
    private let defaults: UserDefaults
    private let key = "kelpie_bookmarks_tree_v1"
    private var loadError: Error?
    private var undoRemoval: (BookmarkTree.Mutation, UUID)?

    init(defaults: UserDefaults = .standard) { self.defaults = defaults; load() }

    func children(of parent: UUID?) -> [Bookmark] { nodes.filter { $0.parentId == parent } }

    func useAccount(_ account: UOAAccount) {
        resetSession()
        nodes = []
        accountBookmarks = AccountBookmarks(account: account, store: self)
        accountBookmarks?.enqueue()
    }

    func useLocalBookmarks() {
        resetSession()
        accountBookmarks = nil
        load()
    }

    private func resetSession() {
        accountBookmarks?.invalidate()
        generation = UUID()
        syncError = nil
        isSyncing = false
        loadError = nil
        undoRemoval = nil
        canUndoRemoval = false
    }

    func refreshAccountBookmarks() { accountBookmarks?.enqueue() }
    func flush() async throws {
        let current = accountBookmarks
        try await current?.flush()
        guard current === accountBookmarks else { throw CancellationError() }
        if let syncError { throw BookmarkTree.Failure(message: syncError) }
    }
    func setAccountBookmarks(_ value: [Bookmark]) { nodes = value }
    func setSyncState(busy: Bool, error: String?) { isSyncing = busy; syncError = error }

    @discardableResult
    func mutate(_ mutation: BookmarkTree.Mutation) -> Task<Void, Error>? {
        if let accountBookmarks { return accountBookmarks.enqueue(mutation) }
        do {
            if let loadError { throw loadError }
            let changed = try mutation.apply(to: nodes)
            let data = try JSONEncoder().encode(changed)
            defaults.set(data, forKey: key)
            nodes = changed
            syncError = nil
            return nil
        } catch {
            syncError = error.localizedDescription
            return Task { throw error }
        }
    }

    @discardableResult
    func add(title: String, url: String, parentId: UUID? = nil) -> Task<Void, Error>? {
        mutate(.add(Bookmark(title: title.isEmpty ? url : title, url: url, parentId: parentId)))
    }

    @discardableResult
    func addPage(title: String, url: String, isStartPage: Bool) -> Bool {
        let node = Bookmark(title: title.isEmpty ? url : title, url: url)
        guard !isStartPage, (try? BookmarkTree.validate(node)) != nil,
              !bookmarks.contains(where: { $0.url == url }) else { return false }
        add(title: node.title, url: url)
        return true
    }

    @discardableResult
    func remove(id: UUID) -> Task<Void, Error>? { mutate(.removeTree(BookmarkTree.subtree(id, in: nodes))) }
    @discardableResult
    func removeAll() -> Task<Void, Error>? { mutate(.clear) }

    /// Save the exact subtree and sibling anchor, never an entire account snapshot.
    func removeWithUndo(id: UUID) async throws {
        let session = generation
        let removed = BookmarkTree.subtree(id, in: nodes)
        guard let root = removed.first else { return }
        let siblings = children(of: root.parentId)
        let position = siblings.firstIndex { $0.id == id } ?? 0
        let next = siblings.dropFirst(position + 1).first?.id
        try await mutate(.removeTree(removed))?.value
        guard generation == session else { throw CancellationError() }
        undoRemoval = (.restore(removed, beforeId: next), session)
        canUndoRemoval = true
    }

    func undoLastRemoval() async throws {
        guard let (mutation, session) = undoRemoval, generation == session else { return }
        try await mutate(mutation)?.value
        guard generation == session else { throw CancellationError() }
        undoRemoval = nil
        canUndoRemoval = false
    }

    func toJSON() -> [[String: Any]] {
        guard let data = try? JSONEncoder().encode(nodes),
              let values = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }
        return values
    }

    private func load() {
        do {
            let raw = defaults.object(forKey: key) ?? defaults.object(forKey: "kelpie_bookmarks")
            let data: Data
            if let stored = raw as? Data {
                data = stored
            } else if let stored = raw as? String {
                data = Data(stored.utf8)
            } else if raw == nil {
                data = Data("[]".utf8)
            } else {
                throw BookmarkTree.Failure(message: "Saved favourites could not be read.")
            }
            nodes = try BookmarkTree.normalized(JSONDecoder().decode([Bookmark].self, from: data))
            loadError = nil
        } catch {
            loadError = error
            syncError = "Saved favourites could not be read. The original data has been preserved."
        }
    }

    nonisolated static func date(from value: String) -> Date? {
        if let date = iso8601Formatter.date(from: value) { return date }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: value)
    }

    nonisolated static var iso8601Formatter: ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }
}
