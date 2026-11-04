# Shared favourites tree and live settings updates

## Data and authority

macOS, iOS and Android use an ordered array of nodes with a stable UUID, title,
URL, creation time, kind (bookmark/folder), and nullable parentId. Array order
sets sibling order. There is no fixed nesting limit. Start-page tiles use a
leaf-only projection; editors and HTTP/MCP return the complete tree.

Swift shares the model and mutations between Apple platforms. Kotlin mirrors
those rules. Local storage uses a versioned key and retains the original flat
blob. Corrupt storage fails closed. Legacy entries become root bookmarks;
orphaned or cyclic parent links normalize in memory without writing on load.
The former flat C++ adapter cannot preserve folders and is removed from these
stores.

Signed-in favourites remain in UOA's existing browser/bookmarks setting. Every
mutation fetches the authoritative array, applies an intention, and commits with
If-Match. Conflict retries repeat the intention against fresh data. Surviving
records retain unknown fields, unchanged records retain their original values,
and foreign records keep their relative positions. Account collections never
persist in the separate local collection.

## Operations

UI and HTTP/MCP share add, create folder, update title/URL, move, remove subtree,
and clear. A move supplies parentId (null for root) and an optional beforeId
sibling anchor, avoiding stale numeric positions during conflict retries. An
update cannot change a parent. Reject missing nodes, invalid URLs, non-folder
parents, duplicate IDs and self/descendant moves. Removing a concurrently changed
subtree fails rather than deleting unseen additions. Clear removes known nodes
while retaining foreign records. UI removal offers account-scoped undo.

## Presentation

The Mac bar uses AppKit-backed buttons so renderer focus cannot consume clicks.
Click or delayed hover opens a folder's native menu below the bar, with recursive
submenus beside it. Native menus adapt at screen edges. Dragging within the bar
reorders roots or nests into a folder. Dragging deliberately outside removes the
item after a successful save and shows a puff animation; Escape cancels. Reduced
motion avoids the expanding effect. The editor is an NSOutlineView with editable
names/URLs, folder creation, add-current-page, deletion, undo, and tree drag/drop.

Phones show a full-screen tree; tablets show a left drawer selected by window
width. iOS and Android provide matching folder disclosure, page navigation,
editing, create-inside/add-page-here, removal/undo, and drag/drop. An explicit
Move action supplies an accessible destination and sibling-position alternative.
Tablet navigation keeps the drawer open. Account-generation checks discard stale
menus, edits, drags and undo after an account switch.

## MCP and cross-device updates

Existing list/add/remove/clear tools remain. Add accepts parentId; new
kelpie_bookmarks_create_folder, kelpie_bookmarks_update and kelpie_bookmarks_move
tools are available on macOS, iOS and Android through the extension gateway.
Native and TypeScript registries, schemas and documentation must agree. Calls
wait for durable local or account success.

UOA adds a generic authenticated settings stream, documented in its repository
at Docs/plans/2026-11-04-settings-stream.md. Clients accept an initial snapshot
and version-matched root splice/replacement deltas. Reconnect obtains a fresh
snapshot. A malformed frame or base-version mismatch triggers reconciliation.
Streams pause during queued writes and restart after them, preventing an old
push from overwriting a newer save. Foregrounding refreshes suspended clients;
mobile background execution is not guaranteed.

## Cross-Provider Review

Claude reviewed the original design and mobile expansion before implementation;
a separate Codex review checked the shared source graph and protocol boundaries.
Accepted findings: versioned migration with retained legacy data, fail-closed
loads, opaque-record preservation, beforeId anchors, generation fencing,
concurrent-subtree deletion checks, leaf-only start pages, native toolbar controls,
window-width presentation, durable Android preference writes, and common mutation
fixtures. Both native and shared MCP registries require validation.

The streaming review selected one root splice or full replacement over RFC6902,
removing three JSON Pointer interpreters. UOA versions are opaque equality tokens;
native clients do not reproduce JavaScript canonical hashing. A database trigger
covers every writer, and LISTEN precedes the initial authoritative snapshot.

## Verification and delivery

Exercise migration, nesting, cycles, reorder anchors, metadata preservation,
conflicts, stale sessions, failed saves and delta validation in focused tests.
Use the actual Mac editor/bar and phone/tablet editors, including drag, undo and
nested navigation. Capture matching base/final screenshots only for changed
states. Run Swift lint and Apple builds/tests on Mac, portable checks on Maxis,
and Android checks on an available Android SDK host. Track deployment, installed
release verification and signed-in multi-device verification separately from
local test results.
