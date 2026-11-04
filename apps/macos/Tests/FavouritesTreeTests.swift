import XCTest
@testable import Kelpie

@MainActor
final class FavouritesTreeTests: XCTestCase {
    typealias Node = BookmarkStore.Bookmark

    func testNestedMovesPreserveDescendantsAndRejectCyclesAndStaleAnchors() throws {
        let folder = Node(title: "Work", kind: .folder)
        let child = Node(title: "Docs", kind: .folder, parentId: folder.id)
        let page = Node(title: "Page", url: "https://example.com", parentId: child.id)
        let other = Node(title: "Other", kind: .folder)
        let nodes = [folder, child, page, other]
        let moved = try BookmarkTree.Mutation.move(child.id, parentId: other.id, beforeId: nil).apply(to: nodes)
        XCTAssertEqual(moved.first { $0.id == page.id }?.parentId, child.id)
        XCTAssertEqual(moved.first { $0.id == child.id }?.parentId, other.id)
        XCTAssertThrowsError(try BookmarkTree.Mutation.move(folder.id, parentId: child.id, beforeId: nil).apply(to: nodes))
        XCTAssertThrowsError(try BookmarkTree.Mutation.move(other.id, parentId: folder.id, beforeId: page.id).apply(to: nodes))
        let reordered = try BookmarkTree.Mutation.move(other.id, parentId: nil, beforeId: folder.id).apply(to: nodes)
        XCTAssertEqual(reordered.filter { $0.parentId == nil }.map(\.id), [other.id, folder.id])
    }

    func testSubtreeRemovalRequiresExactFreshContentsAndUndoPreservesOtherEdits() throws {
        let folder = Node(title: "Work", kind: .folder)
        let page = Node(title: "Page", url: "https://example.com", parentId: folder.id)
        let other = Node(title: "Other", url: "https://other.example")
        let original = [folder, page, other]
        let removed = BookmarkTree.subtree(folder.id, in: original)
        let mutation = BookmarkTree.Mutation.removeTree(removed)
        XCTAssertEqual(try mutation.apply(to: original), [other])
        let concurrent = Node(title: "New", url: "https://new.example", parentId: folder.id)
        XCTAssertThrowsError(try mutation.apply(to: original + [concurrent]))
        var renamed = other
        renamed.title = "Renamed elsewhere"
        let restored = try BookmarkTree.Mutation.restore(removed, beforeId: other.id).apply(to: [renamed])
        XCTAssertEqual(restored, [folder, page, renamed])
        XCTAssertThrowsError(try BookmarkTree.Mutation.restore(removed, beforeId: nil).apply(to: restored))
    }

    func testLocalMigrationKeepsOriginalAndFoldersOutOfStartPageProjection() async throws {
        let suite = "FavouritesTreeTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let legacy = Data(#"[{"title":"Example","url":"https://example.com"}]"#.utf8)
        defaults.set(legacy, forKey: "kelpie_bookmarks")
        let store = BookmarkStore(defaults: defaults)
        XCTAssertEqual(store.bookmarks.count, 1)
        let folder = Node(title: "Folder", kind: .folder)
        try await store.mutate(.add(folder))?.value
        XCTAssertEqual(store.nodes.count, 2)
        XCTAssertEqual(store.bookmarks.count, 1)
        XCTAssertEqual(defaults.data(forKey: "kelpie_bookmarks"), legacy)
        XCTAssertEqual(BookmarkStore(defaults: defaults).nodes, store.nodes)
        try await store.removeWithUndo(id: folder.id)
        try await store.undoLastRemoval()
        XCTAssertEqual(store.nodes.last?.id, folder.id)
        defaults.set(Data("corrupt".utf8), forKey: "kelpie_bookmarks_tree_v1")
        let corrupt = BookmarkStore(defaults: defaults)
        do { try await corrupt.mutate(.add(folder))?.value; XCTFail("Must not overwrite corrupt data") } catch { }
        XCTAssertEqual(defaults.data(forKey: "kelpie_bookmarks_tree_v1"), Data("corrupt".utf8))
    }

    func testSettingsDeltaIsAtomicAndRequiresMatchingBase() throws {
        var state = UOASettingsValue()
        let first = "\"" + String(repeating: "a", count: 64) + "\""
        let next = "\"" + String(repeating: "b", count: 64) + "\""
        func frame(_ fields: [String: Any]) throws -> Data {
            try JSONSerialization.data(withJSONObject: ["protocolVersion": 1, "namespace": "browser", "key": "bookmarks"].merging(fields) { _, new in new })
        }
        XCTAssertTrue(try state.receive(frame(["type": "settings.snapshot", "version": first, "value": ["a", "b", "c"]]), namespace: "browser", key: "bookmarks"))
        let invalid: [String: Any] = ["type": "settings.delta", "version": next, "baseVersion": first,
                                     "operation": ["type": "splice", "index": 8, "deleteCount": 1, "items": []]]
        XCTAssertThrowsError(try state.receive(frame(invalid), namespace: "browser", key: "bookmarks"))
        XCTAssertEqual(state.version, first)
        XCTAssertEqual(state.value as? [String], ["a", "b", "c"])
        var valid = invalid
        valid["operation"] = ["type": "splice", "index": 1, "deleteCount": 1, "items": ["new"]]
        XCTAssertTrue(try state.receive(frame(valid), namespace: "browser", key: "bookmarks"))
        XCTAssertEqual(state.value as? [String], ["a", "new", "c"])
        XCTAssertFalse(try state.receive(frame(valid), namespace: "browser", key: "bookmarks"))
        valid["version"] = first
        XCTAssertThrowsError(try state.receive(frame(valid), namespace: "browser", key: "bookmarks"))
        valid["protocolVersion"] = true
        XCTAssertThrowsError(try state.receive(frame(valid), namespace: "browser", key: "bookmarks"))
    }
}
