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
    private var pending: Task<Void, Error>?
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

    @discardableResult
    func enqueue(_ mutation: Mutation? = nil) -> Task<Void, Error> {
        let previous = pending
        let operation = Task { [weak self] in
            _ = try? await previous?.value
            guard let self, self.active, !Task.isCancelled else { throw CancellationError() }
            self.store?.setSyncState(busy: true, error: nil)
            do {
                let bookmarks = try await self.perform(mutation)
                guard self.active else { throw CancellationError() }
                self.store?.setAccountBookmarks(bookmarks)
                self.store?.setSyncState(busy: false, error: nil)
            } catch {
                guard self.active else { throw CancellationError() }
                self.store?.setSyncState(busy: false, error: error.localizedDescription)
                throw error
            }
        }
        pending = operation
        return operation
    }

    func flush() async throws { try await pending?.value }

    private func perform(_ mutation: Mutation?) async throws -> [BookmarkStore.Bookmark] {
        for attempt in 0..<3 {
            let response = try await request(path, "GET", nil, nil)
            guard active, !Task.isCancelled else { throw CancellationError() }
            let original = try Self.values(from: response.data)
            let existing = Self.bookmarks(in: original)
            guard let mutation else { return existing }
            guard let version = response.version else { throw UOATransport.Failure(status: 428) }
            // Other UOA clients may attach favicon/folder metadata. Preserve their
            // opaque fields when changing a different item in the shared list.
            let values: [Any]
            switch mutation {
            case .add(let bookmark):
                values = existing.contains(where: { $0.url == bookmark.url }) ? original
                    : original + [try JSONSerialization.jsonObject(with: JSONEncoder().encode(bookmark))]
            case .remove(let id):
                values = original.filter { Self.bookmark($0)?.id != id }
            case .clear: values = []
            }
            let body = try JSONSerialization.data(withJSONObject: ["value": values])
            do {
                let saved = try await request(path, "PUT", body, version)
                guard active else { throw CancellationError() }
                return Self.bookmarks(in: try Self.values(from: saved.data))
            } catch let failure as UOATransport.Failure where failure.status == 409 && attempt < 2 {
                continue
            }
        }
        throw UOATransport.Failure(status: 409)
    }

    private static func values(from data: Data) throws -> [Any] {
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let value = object?["value"], !(value is NSNull) else { return [] }
        guard let values = value as? [Any] else { throw UOATransport.Failure(status: 422) }
        return values
    }

    private static func bookmark(_ value: Any) -> BookmarkStore.Bookmark? {
        guard JSONSerialization.isValidJSONObject(value),
              let data = try? JSONSerialization.data(withJSONObject: value),
              let bookmark = try? JSONDecoder().decode(BookmarkStore.Bookmark.self, from: data),
              !bookmark.url.isEmpty else { return nil }
        return bookmark
    }

    private static func bookmarks(in values: [Any]) -> [BookmarkStore.Bookmark] {
        var seen = Set<UUID>()
        return values.compactMap(bookmark).filter { seen.insert($0.id).inserted }
    }
}
