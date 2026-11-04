import Foundation
import CryptoKit

extension BookmarkStore {
    struct Bookmark: Identifiable, Codable, Equatable {
        enum Kind: String, Codable { case bookmark, folder }
        let id: UUID
        var title: String
        var url: String
        var createdAt: Date
        var kind: Kind
        var parentId: UUID?
        var isFolder: Bool { kind == .folder }

        init(title: String, url: String = "", kind: Kind = .bookmark, parentId: UUID? = nil) {
            id = UUID()
            self.title = title
            self.url = url
            createdAt = Date(timeIntervalSince1970: floor(Date().timeIntervalSince1970))
            self.kind = kind
            self.parentId = parentId
        }

        private enum CodingKeys: String, CodingKey { case id, title, url, createdAt, created_at, name, kind, parentId }

        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            url = try values.decodeIfPresent(String.self, forKey: .url) ?? ""
            kind = try values.decodeIfPresent(Kind.self, forKey: .kind) ?? .bookmark
            let identifier = try values.decodeIfPresent(String.self, forKey: .id) ?? ""
            let digest = Array(SHA256.hash(data: Data(url.utf8)).prefix(16))
            let fallback = digest.withUnsafeBytes { UUID(uuid: $0.loadUnaligned(as: uuid_t.self)) }
            guard !isEmptyFolderID(kind: kind, identifier: identifier) else {
                throw DecodingError.dataCorruptedError(forKey: .id, in: values, debugDescription: "Folders require a stable UUID")
            }
            id = UUID(uuidString: identifier) ?? fallback
            title = (try? values.decode(String.self, forKey: .title))
                ?? (try? values.decode(String.self, forKey: .name)) ?? url
            parentId = try values.decodeIfPresent(UUID.self, forKey: .parentId)
            createdAt = (try? values.decode(Date.self, forKey: .createdAt))
                ?? (try? values.decode(String.self, forKey: .createdAt)).flatMap(BookmarkStore.date)
                ?? (try? values.decode(String.self, forKey: .created_at)).flatMap(BookmarkStore.date)
                ?? Date(timeIntervalSince1970: 0)
        }

        func encode(to encoder: Encoder) throws {
            var values = encoder.container(keyedBy: CodingKeys.self)
            try values.encode(id.uuidString, forKey: .id)
            try values.encode(title, forKey: .title)
            try values.encode(url, forKey: .url)
            try values.encode(BookmarkStore.iso8601Formatter.string(from: createdAt), forKey: .createdAt)
            try values.encode(kind, forKey: .kind)
            try values.encode(parentId, forKey: .parentId)
        }
    }
}

private func isEmptyFolderID(kind: BookmarkStore.Bookmark.Kind, identifier: String) -> Bool {
    kind == .folder && UUID(uuidString: identifier) == nil
}
