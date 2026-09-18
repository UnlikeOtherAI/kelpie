#pragma once

#include <cstddef>
#include <map>
#include <string>
#include <vector>

#include "include/cef_request_context.h"

namespace kelpie {

// One CefRequestContext per storage partition.
//
// Concurrency: every method touches CEF objects, so the registry is owner
// (CEF UI) thread only, exactly like DesktopEngine::Impl::tabs. It holds no
// lock of its own and never calls back into the engine, so no lock is ever
// held across a CEF callback.
class DesktopPartitionRegistry {
 public:
  struct Entry {
    std::string id;
    CefRefPtr<CefRequestContext> context;
    // Fixed by the first tab to resolve this partition. A later tab asking for
    // the other value joins the existing store rather than splitting it.
    bool persistent = true;
    // Set for the window between `delete-partition` starting and the entry
    // being erased. A `new-tab` naming a deleting partition is refused instead
    // of binding to a store that is about to disappear.
    bool deleting = false;
    std::size_t tab_count = 0;
  };

  // `root` is <profile>/partitions. Empty means no on-disk location is
  // available, so every partition is forced in-memory.
  void SetRoot(std::string root);
  const std::string& root() const { return root_; }

  Entry* Find(const std::string& id);
  const Entry* Find(const std::string& id) const;
  // First-resolve-wins: an existing entry is returned unchanged whatever
  // persistence the caller asked for. Returns nullptr when CEF refused to
  // create the context.
  Entry* Acquire(const std::string& id, bool persistent);
  void Erase(const std::string& id);
  std::vector<Entry*> Entries();
  bool empty() const { return entries_.empty(); }

  std::string DirectoryFor(const std::string& id) const;

  // Deletes the partition's directory. Chromium can still hold file handles
  // moments after the context is released, so a failed delete falls back to a
  // rename into <root>/.trash/<id>-<epoch> — which the next launch purges —
  // rather than reporting a success that left the data in place.
  bool RemoveStorage(const std::string& id) const;

  // Removes <root>/.trash. Call once at startup, before any context exists.
  static void PurgeTrash(const std::string& root);

 private:
  std::string root_;
  // std::map for pointer stability: callers hold an Entry* across a browser
  // creation, which can itself insert another partition.
  std::map<std::string, Entry> entries_;
};

}  // namespace kelpie
