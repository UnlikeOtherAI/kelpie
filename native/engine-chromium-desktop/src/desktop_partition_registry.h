#pragma once

#include <atomic>
#include <cstddef>
#include <map>
#include <string>
#include <vector>

#include "include/cef_request_context.h"
#include "include/cef_request_context_handler.h"

namespace kelpie {

// A persistent request context loads a Chromium profile from disk before it can
// host a browser, and CreateBrowserSync against one that has not finished
// simply returns null. This handler is how the engine knows when to stop
// waiting.
class PartitionContextHandler : public CefRequestContextHandler {
 public:
  void OnRequestContextInitialized(CefRefPtr<CefRequestContext>) override {
    initialized_.store(true);
  }

  bool initialized() const { return initialized_.load(); }

 private:
  std::atomic<bool> initialized_{false};

  IMPLEMENT_REFCOUNTING(PartitionContextHandler);
};

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
    CefRefPtr<PartitionContextHandler> handler;
    // Fixed by the first tab to resolve this partition. A later tab asking for
    // the other value joins the existing store rather than splitting it.
    bool persistent = true;
    // Set for the window between `delete-partition` starting and the entry
    // being erased. A `new-tab` naming a deleting partition is refused instead
    // of binding to a store that is about to disappear.
    bool deleting = false;
    std::size_t tab_count = 0;

    // False until Chromium has finished loading the store. A browser created
    // before then is never created at all.
    bool ready() const { return handler && handler->initialized(); }
  };

  // `root` is the Chromium cache root (CefSettings.root_cache_path). CEF
  // treats a request-context cache_path as a profile directory directly under
  // that root, so each partition store is a direct child named
  // `partition-<id>` -- a nested `partitions/<id>` path is ignored and the
  // store silently falls back to memory. Empty means no on-disk location is
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
  // Releases every context. CEF requires that no reference to a CEF object
  // survives CefShutdown, and a context still referenced at that point never
  // gets the chance to flush its store to disk.
  void Clear();
  std::vector<Entry*> Entries();
  bool empty() const { return entries_.empty(); }

  std::string DirectoryFor(const std::string& id) const;

  // Deletes a partition's directory. Pure filesystem work with no CEF in it,
  // so the caller runs it off the owner thread and can retry: Chromium keeps
  // the profile's files open for a short while after the context is released.
  // A directory that stays locked is renamed into the trash — which the next
  // launch purges — rather than reported as a successful deletion.
  static bool RemoveStorage(const std::string& root, const std::string& id);

  // Removes <root>/.trash. Call once at startup, before any context exists.
  static void PurgeTrash(const std::string& root);

 private:
  std::string root_;
  // std::map for pointer stability: callers hold an Entry* across a browser
  // creation, which can itself insert another partition.
  std::map<std::string, Entry> entries_;
};

}  // namespace kelpie
