# macOS favourites tree

## Scope and existing limitation

The macOS favourites bar currently renders every saved URL in one flat row. Its
store bridges through a flat C++ record, which drops folder metadata. The editor
is a navigation-only list. Extend the Mac experience; mobile UI is unchanged.

## Data and mutations

Keep one ordered flat array of nodes, with stable UUID, title, URL, createdAt,
kind (bookmark/folder), and nullable parentId. Array order determines sibling
order. Legacy records decode as root bookmarks. Replace the Mac-only C++ store
adapter with direct Codable persistence under the existing UserDefaults key;
this removes a lossy round trip and leaves other platform stores unchanged.
Account storage remains UOA's existing bookmark settings endpoint. Apply typed
intentions against each fresh GET on conflict retries, preserving opaque fields
on surviving records. Never persist account bookmarks in the local collection.

One validated mutation implementation serves UI and HTTP/MCP: add bookmark,
create folder, update title/URL, move to parent and sibling index, remove subtree,
and clear. Reject missing nodes, non-folder parents, self/descendant moves, bad
URLs and out-of-range positions. Delete folders recursively. Decode legacy data
without losing entries; orphaned/cyclic parent links appear at root and are
normalized by the same deterministic tree validation. No fixed nesting limit.

## Native UI

AppKit NSButton-backed favourites provide click navigation and drag tracking.
Folder click or a short deliberate hover opens NSMenu beneath the bar; native
submenus cascade beside it and adapt at screen edges. Keyboard access is native.
A drag starts only after a movement threshold. Dropping outside the bar removes
the item with the system disappearing-item puff only after a successful save;
Escape cancels. Dropping within the bar reorders or moves into a folder. Capture
the source store/account generation so switching accounts cancels stale drags.

Replace the existing bookmarks sheet content with an NSOutlineView tree editor,
reachable through the existing Bookmarks action and bar context menu. It supports
new folders, add current page, editing names/URLs, deletion, sibling reordering,
and moves into/out of folders. Native outline disclosure, drop validation, and
selection provide the tree interaction. Show save failures and keep failed items.
Start-page URL tiles continue showing bookmarks only, never folder pseudo-URLs.

## HTTP and MCP

Keep the existing list/add/remove/clear operations. List returns enriched flat
nodes with parentId and kind. Add accepts optional parentId and index on macOS.
Add macOS-only bookmarks-create-folder, bookmarks-update, bookmarks-move routes
and matching kelpie_ extensions through the existing MCP extension gateway.
Schemas, shared TypeScript tool map/client routing and reference docs must agree.
No renderer dependency; API mutations wait for durable local/account success.

## Verification and delivery

Targeted tests cover migration, persistence, nesting, reorder indices, cycle
rejection, recursive deletion, account conflicts and metadata preservation,
failed saves, drag cancellation and MCP schema/dispatch. Manually use the base
and final Mac UI for matching screenshots, including focused WebKit/Chromium,
folder hover/click, cascading submenu, tree editing and drag/drop removal. Run
Swift lint, Mac build/tests and applicable CLI/shared checks, with portable work
on Maxis. Publish affected component releases, install the published Mac app,
verify it, merge the single reviewed PR when checks pass and clean the worktree.

## Cross-Provider Review

Pending before implementation.

### Claude review decisions

Accepted: use a versioned local key and retain the legacy blob; fail closed on
corrupt stored data; preserve opaque account fields; share URL validation; use
beforeId anchors for retry-safe moves (null means append); distinguish cancelled
and successful drag sessions; validate folder/URL combinations; revalidate menu
selections against current state; report account failures and support undo for UI
removal. Drag into nested folders belongs in the outline, not NSMenu.

Clarifications: the array model remains useful for the existing UOA value and
flat API compatibility. A typed kind with validated URL rules is sufficient.
Parent omission on add means root; move requires parentId (null for root), while
update cannot change the parent. Invalid imported parent links are repaired in
memory deterministically, not written on load. Concurrent subtree changes cause
removal to fail rather than delete unseen additions. Native mouse tracking will
explicitly distinguish Escape from release, and removal requires a deliberate
distance outside the bar. Hover opening remains required by the user's brief;
it is delayed and disabled during drags. Other platforms still use the C++ store.

### Codex review decisions

Accepted: iOS compiles the existing store and account sync sources. Keep `nodes`
as the full tree and `bookmarks` as a leaf-only projection, with legacy leaf-only
JSON for iOS and explicit tree JSON for Mac. Mac bar visibility and underlap use
nodes so empty folders remain visible. Preserve unrelated undecodable account
records as well as unknown fields. Verify both native and shared MCP registries.
The iOS source graph changes and requires its native build check.

## Expanded mobile and tablet scope (user clarification)

Supersedes the Mac-only UI scope above. iOS and Android expose the same folder
nodes, operations, and MCP contracts as Mac. Phones open a full-screen favourites
tree; tablets open a left-side drawer. Both provide folder disclosure, bookmark
navigation, new folder/add current, rename/edit URL, deletion with undo, and
long-press drag/drop to reorder siblings or nest in folders. An explicit Move
control provides an accessible alternative to drag/drop and allows moving back
to the root. Mac retains the top-bar-specific puff gesture and cascading menus.

Swift tree logic is shared by iOS and macOS. Android mirrors its typed ordered
node model and validated mutations. Remove the Android flat C++ persistence
adapter too; keep old local storage untouched and migrate to a versioned key.
Both sync implementations apply intentions against the raw account array,
preserve unknown records/fields, and return success only after the save commits.
Start-page tiles on each platform remain leaf-only views; all editor/API reads
use the tree. Availability for the new routes is iOS, Android and macOS only.

Verification now includes phone and tablet UI on iOS and Android, with before/
after screenshots of the changed surfaces. Build Android on Ubuntu (Android SDK)
and Apple apps on Mac. CLI/shared checks run on Maxis. Bump and publish all four
affected components and install/verify their released artifacts where possible;
report concrete hardware/signing/install blockers without claiming completion.

### Mobile review decisions

Both providers reviewed the mobile expansion before its implementation. Accepted:
change presentation hosts, use window width for the drawer, mirror before/inside/
after and root drag targets, preserve account-scoped undo, commit Android local
writes before acknowledging success, and use common mutation fixtures. Existing
start-page tile projections remain URL-only. Clear removes known nodes, preserving
foreign account records. Duplicate URL prevention is scoped to the destination
folder; the address-bar shortcut still avoids creating a duplicate saved URL.
