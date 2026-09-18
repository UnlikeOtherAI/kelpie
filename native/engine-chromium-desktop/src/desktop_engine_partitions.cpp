#include "desktop_engine_impl.h"

#include <chrono>
#include <memory>
#include <thread>
#include <utility>
#include <vector>

#include "kelpie/partition.h"
#if defined(_WIN32)
#include <windows.h>
#endif

// The storage-partition lifecycle: keeping the registry's view of the live
// tabs honest, listing what exists, and tearing one down. Tab creation binds a
// partition in desktop_engine_control.cpp, where the browser is made.

namespace kelpie {

void DesktopEngine::Impl::RecountPartitions() {
  for (DesktopPartitionRegistry::Entry* entry : partitions.Entries()) entry->tab_count = 0;
  for (const Tab& tab : tabs) {
    if (tab.closing || !tab.partition) continue;
    if (auto* entry = partitions.Find(*tab.partition)) ++entry->tab_count;
  }
  // A partition exists only while something references it. A persistent store
  // keeps its id after the last tab closes so it can be listed and deleted; an
  // in-memory store has nothing left to name once its context is released.
  for (DesktopPartitionRegistry::Entry* entry : partitions.Entries()) {
    if (entry->tab_count == 0 && !entry->persistent && !entry->deleting) {
      partitions.Erase(entry->id);
    }
  }
}

BrowserControlResult DesktopEngine::GetPartitions(std::vector<PartitionInfo>* output,
                                                  Timeout timeout) {
  const auto impl = impl_;
  if (output == nullptr) return BrowserControlResult::Failure("INTERNAL", "partitions is required");
  auto collected = std::make_shared<std::vector<PartitionInfo>>();
  const auto result = impl->RunOnUi([impl, collected] {
    impl->RecountPartitions();
    collected->clear();
    for (const DesktopPartitionRegistry::Entry* entry : impl->partitions.Entries()) {
      collected->push_back({entry->id, entry->tab_count, entry->persistent});
    }
    return BrowserControlResult::Success();
  }, timeout);
  if (result.ok) *output = std::move(*collected);
  return result;
}

BrowserControlResult DesktopEngine::DeletePartition(const std::string& id,
                                                    PartitionDeletion* deletion, Timeout timeout) {
  const auto impl = impl_;
  if (deletion == nullptr) return BrowserControlResult::Failure("INTERNAL", "deletion is required");
  const PartitionValidation validation = ValidatePartition(id);
  if (!validation.ok) {
    return BrowserControlResult::Failure(
        "INVALID_PARTITION",
        "Invalid partition \"" + id + "\": " + PartitionErrorMessage(validation.reason));
  }
  auto outcome = std::make_shared<PartitionDeletion>();
  // Phase one marks the partition deleting and force-closes its tabs. CEF only
  // releases the store's files once every browser has reported OnBeforeClose,
  // so the directory removal cannot run in the same UI-thread turn.
  const auto marked = impl->RunOnUi([impl, id, outcome] {
    auto* entry = impl->partitions.Find(id);
    if (entry == nullptr) {
      outcome->existed = false;
      return BrowserControlResult::Success();
    }
    outcome->existed = true;
    entry->deleting = true;
    std::vector<CefRefPtr<CefBrowser>> closing;
    for (Impl::Tab& tab : impl->tabs) {
      if (tab.closing || !tab.partition || *tab.partition != id) continue;
      tab.closing = true;
      if (tab.devtools) tab.devtools->CancelAll();
      closing.push_back(tab.browser);
    }
    outcome->tabs_closed = closing.size();
    std::size_t live_tabs = 0;
    for (const Impl::Tab& tab : impl->tabs) {
      if (!tab.closing) ++live_tabs;
    }
    if (live_tabs == 0) {
      // The window must never be left with no tab, the same rule close-tab
      // follows. A replacement in the default store is what a user expects.
      TabSnapshot replacement;
      impl->CreateTabOnUi("about:blank", &replacement);
    }
    for (const auto& browser : closing) {
      if (browser && browser->GetHost()) browser->GetHost()->CloseBrowser(true);
    }
    for (const Impl::Tab& tab : impl->tabs) {
      if (!tab.closing) {
        impl->browser = tab.browser;
        break;
      }
    }
#if defined(_WIN32)
    if (impl->browser && impl->browser->GetHost()) {
      ShowWindow(impl->browser->GetHost()->GetWindowHandle(), SW_SHOW);
    }
#endif
    impl->UpdateActiveState();
    return BrowserControlResult::Success();
  }, timeout);
  if (!marked.ok) return marked;
  if (!outcome->existed) {
    *deletion = *outcome;
    return BrowserControlResult::Success();
  }

  // Wait for CEF to deliver OnBeforeClose for those browsers before releasing
  // the context, otherwise the storage files are certain to still be locked.
  const auto deadline = std::chrono::steady_clock::now() + timeout;
  while (std::chrono::steady_clock::now() < deadline) {
    auto remaining = std::make_shared<std::size_t>(0);
    const auto probe = impl->RunOnUi([impl, id, remaining] {
      for (const Impl::Tab& tab : impl->tabs) {
        if (tab.partition && *tab.partition == id) ++*remaining;
      }
      return BrowserControlResult::Success();
    }, std::chrono::milliseconds(500));
    if (!probe.ok || *remaining == 0) break;
    std::this_thread::sleep_for(std::chrono::milliseconds(10));
  }

  auto partitions_root = std::make_shared<std::string>();
  const auto removed = impl->RunOnUi([impl, id, partitions_root] {
    *partitions_root = impl->partitions.root();
    impl->partitions.Erase(id);
    return BrowserControlResult::Success();
  }, timeout);
  if (!removed.ok) return removed;
  // Chromium keeps the profile's files open briefly after the context is
  // released, so the first unlink loses a race it wins a moment later.
  // Retrying here, off the owner thread, is what turns the common case into a
  // real deletion rather than a trashed directory and a PARTITION_IN_USE.
  // Its own small budget: the wait above may already have spent the caller's,
  // and giving up instantly here is what leaves a directory in the trash.
  const auto removal_deadline = std::chrono::steady_clock::now() + std::chrono::seconds(3);
  bool released = false;
  do {
    released = DesktopPartitionRegistry::RemoveStorage(*partitions_root, id);
    if (released) break;
    std::this_thread::sleep_for(std::chrono::milliseconds(100));
  } while (std::chrono::steady_clock::now() < removal_deadline);
  *deletion = *outcome;
  if (!released) {
    // The id is freed either way. The caller must not be told the data is gone
    // while Chromium still owns the files.
    return BrowserControlResult::Failure(
        "PARTITION_IN_USE",
        "Partition " + id + " was closed but Chromium still holds its storage files");
  }
  return BrowserControlResult::Success();
}

}  // namespace kelpie
