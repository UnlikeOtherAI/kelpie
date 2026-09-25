import Foundation

/// Applies intentions to the latest server list, with compare-and-set protection.
@MainActor
final class AccountBookmarks {
    enum Mutation {
        case add(BookmarkStore.Bookmark)
        case remove(UUID)
        case clear

        func apply(to bookmarks: [BookmarkStore.Bookmark]) -> [BookmarkStore.Bookmark] {
            switch self {
            case .add(let bookmark):
                return bookmarks.contains(where: { $0.url == bookmark.url }) ? bookmarks : bookmarks + [bookmark]
            case .remove(let id): return bookmarks.filter { $0.id != id }
            case .clear: return []
            }
        }
    }

    typealias Request = (String, String, Data?, String?) async throws -> UOATransport.Response
    private let request: Request
    private weak var store: BookmarkStore?
    private var pending: Task<Void, Never>?
    private var active = true
    private let path = "/oauth/me/settings/browser/bookmarks"

    init(account: UOAAccount, store: BookmarkStore) {
        self.request = { try await account.request($0, method: $1, body: $2, version: $3) }
        self.store = store
    }

    init(store: BookmarkStore, request: @escaping Request) {
        self.store = store
        self.request = request
    }

    func invalidate() {
        active = false
        pending?.cancel()
    }

    func enqueue(_ mutation: Mutation? = nil) {
        let previous = pending
        pending = Task { [weak self] in
            await previous?.value
            guard let self, self.active, !Task.isCancelled else { return }
            self.store?.setSyncState(busy: true, error: nil)
            do {
                let bookmarks = try await self.perform(mutation)
                guard self.active else { return }
                self.store?.setAccountBookmarks(bookmarks)
                self.store?.setSyncState(busy: false, error: nil)
            } catch {
                guard self.active else { return }
                self.store?.setSyncState(busy: false, error: error.localizedDescription)
            }
        }
    }

    func flush() async { await pending?.value }

    private func perform(_ mutation: Mutation?) async throws -> [BookmarkStore.Bookmark] {
        struct Envelope: Codable { let value: [BookmarkStore.Bookmark]? }
        for attempt in 0..<3 {
            let response = try await request(path, "GET", nil, nil)
            guard active, !Task.isCancelled else { throw CancellationError() }
            let existing = try JSONDecoder().decode(Envelope.self, from: response.data).value ?? []
            guard let mutation else { return existing }
            guard let version = response.version else { throw UOATransport.Failure(status: 428) }
            let updated = mutation.apply(to: existing)
            // Other UOA clients may attach favicon/folder metadata. Preserve their
            // opaque fields when changing a different item in the shared list.
            let object = try JSONSerialization.jsonObject(with: response.data) as? [String: Any]
            let original = object?["value"] as? [Any] ?? []
            let values: [Any] = try updated.map { bookmark in
                if let index = existing.firstIndex(where: { $0.id == bookmark.id }), index < original.count {
                    return original[index]
                }
                return try JSONSerialization.jsonObject(with: JSONEncoder().encode(bookmark))
            }
            let body = try JSONSerialization.data(withJSONObject: ["value": values])
            do {
                let saved = try await request(path, "PUT", body, version)
                guard active else { throw CancellationError() }
                return try JSONDecoder().decode(Envelope.self, from: saved.data).value ?? []
            } catch let failure as UOATransport.Failure where failure.status == 409 && attempt < 2 {
                continue
            }
        }
        throw UOATransport.Failure(status: 409)
    }
}
