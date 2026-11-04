import Foundation

/// One ordered node collection; sibling order is its array order. Mutations replay
/// against the latest account value rather than replacing an old snapshot.
enum BookmarkTree {
    typealias Node = BookmarkStore.Bookmark

    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    enum Mutation {
        case add(Node)
        case update(UUID, title: String?, url: String?)
        case move(UUID, parentId: UUID?, beforeId: UUID?)
        case remove(UUID)
        case removeTree([Node])
        case restore([Node], beforeId: UUID?)
        case clear

        func apply(to original: [Node]) throws -> [Node] {
            var nodes = original
            switch self {
            case .add(let node):
                try BookmarkTree.validate(node)
                try BookmarkTree.validateParent(node.parentId, in: nodes)
                guard !nodes.contains(where: { $0.id == node.id }) else { return nodes }
                if !node.isFolder && nodes.contains(where: { !$0.isFolder && $0.url == node.url && $0.parentId == node.parentId }) { return nodes }
                nodes.append(node)
            case let .update(id, title, url):
                let index = try BookmarkTree.index(id, in: nodes)
                if let title { nodes[index].title = title }
                if let url { nodes[index].url = url }
                try BookmarkTree.validate(nodes[index])
            case let .move(id, parentId, beforeId):
                nodes = try BookmarkTree.moving(id, parentId: parentId, beforeId: beforeId, in: nodes)
            case .remove(let id):
                // Existing mobile remove operations remove only URL nodes.
                guard let node = nodes.first(where: { $0.id == id }) else { return nodes }
                guard !node.isFolder else { throw Failure(message: "Use subtree removal for folders.") }
                nodes.removeAll { $0.id == id }
            case .removeTree(let expected):
                guard let root = expected.first else { return nodes }
                let current = BookmarkTree.subtree(root.id, in: nodes)
                guard current == expected else {
                    throw Failure(message: "This folder changed on another device. Review it before removing it.")
                }
                let ids = Set(expected.map(\.id))
                nodes.removeAll { ids.contains($0.id) }
            case let .restore(removed, beforeId):
                nodes = try BookmarkTree.restoring(removed, beforeId: beforeId, in: nodes)
            case .clear: nodes = []
            }
            return nodes
        }
    }

    private static func restoring(_ removed: [Node], beforeId: UUID?, in original: [Node]) throws -> [Node] {
        var nodes = original
        guard let root = removed.first else { return nodes }
        guard Set(nodes.map(\.id)).isDisjoint(with: removed.map(\.id)) else {
            throw Failure(message: "These favourites have already been restored.")
        }
        try Self.validateParent(root.parentId, in: nodes)
        let position = beforeId.flatMap { id in nodes.firstIndex { $0.id == id && $0.parentId == root.parentId } } ?? nodes.endIndex
        nodes.insert(contentsOf: removed, at: position)
        return nodes
    }

    private static func moving(_ id: UUID, parentId: UUID?, beforeId: UUID?, in original: [Node]) throws -> [Node] {
        var nodes = original
        let index = try Self.index(id, in: nodes)
        try Self.validateParent(parentId, in: nodes)
        let descendants = Set(Self.subtree(id, in: nodes).map(\.id))
        guard parentId.map({ !descendants.contains($0) }) ?? true else {
            throw Failure(message: "A folder cannot be moved inside itself.")
        }
        guard beforeId != id else { return nodes }
        var node = nodes.remove(at: index)
        node.parentId = parentId
        if let beforeId {
            let destination = try Self.index(beforeId, in: nodes)
            guard nodes[destination].parentId == parentId else {
                throw Failure(message: "The destination has changed. Choose it again.")
            }
            nodes.insert(node, at: destination)
        } else { nodes.append(node) }
        return nodes
    }

    static func validate(_ node: Node) throws {
        guard !node.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw Failure(message: "Enter a name.")
        }
        if node.isFolder {
            guard node.url.isEmpty else { throw Failure(message: "Folders cannot have a URL.") }
        } else {
            guard let url = URL(string: node.url), ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
                  let host = url.host, !host.isEmpty else {
                throw Failure(message: "Enter an HTTP or HTTPS URL with a host.")
            }
        }
    }

    static func validateParent(_ parent: UUID?, in nodes: [Node]) throws {
        guard let parent else { return }
        guard nodes.contains(where: { $0.id == parent && $0.isFolder }) else {
            throw Failure(message: "The destination folder no longer exists.")
        }
    }

    static func index(_ id: UUID, in nodes: [Node]) throws -> Int {
        guard let index = nodes.firstIndex(where: { $0.id == id }) else {
            throw Failure(message: "This favourite no longer exists.")
        }
        return index
    }

    static func subtree(_ id: UUID, in nodes: [Node]) -> [Node] {
        guard let root = nodes.first(where: { $0.id == id }) else { return [] }
        var ids: Set<UUID> = [id]
        var result = [root]
        var position = 0
        while position < result.count {
            let parent = result[position].id
            for child in nodes where child.parentId == parent && ids.insert(child.id).inserted { result.append(child) }
            position += 1
        }
        return result
    }

    /// Broken imported links become roots in memory. The original blob is not
    /// overwritten on load, and duplicate IDs fail closed rather than lose data.
    static func normalized(_ original: [Node]) throws -> [Node] {
        guard Set(original.map(\.id)).count == original.count else { throw Failure(message: "Duplicate favourite IDs in saved data.") }
        var nodes = original
        let folders = Set(nodes.filter(\.isFolder).map(\.id))
        for index in nodes.indices {
            if let parent = nodes[index].parentId, !folders.contains(parent) { nodes[index].parentId = nil }
            var seen: Set<UUID> = [nodes[index].id]
            var parent = nodes[index].parentId
            while let id = parent {
                if !seen.insert(id).inserted { nodes[index].parentId = nil; break }
                parent = nodes.first { $0.id == id }?.parentId
            }
        }
        return nodes
    }
}
