#include "desktop_partition_registry.h"

// CreateContext takes a CefRequestContextHandler; the forward declaration in
// cef_request_context.h is not enough to destroy the scoped_refptr argument.
#include "include/cef_request_context_handler.h"

#include <chrono>
#include <filesystem>
#include <system_error>

namespace kelpie {
namespace {

// Prefix, not a subdirectory: CEF only accepts a profile directory sitting
// directly under root_cache_path, and the prefix keeps partition stores from
// colliding with Chromium's own directories there.
constexpr const char* kPartitionDirectoryPrefix = "partition-";

std::filesystem::path TrashRoot(const std::string& root) {
  return std::filesystem::path(root) / ".kelpie-partition-trash";
}

std::string EpochSuffix() {
  const auto now = std::chrono::system_clock::now().time_since_epoch();
  return std::to_string(std::chrono::duration_cast<std::chrono::milliseconds>(now).count());
}

}  // namespace

void DesktopPartitionRegistry::SetRoot(std::string root) {
  root_ = std::move(root);
}

std::string DesktopPartitionRegistry::DirectoryFor(const std::string& id) const {
  if (root_.empty()) return std::string();
  // The validator has already rejected separators, `.` and `..`, so appending
  // the id cannot escape the root.
  return (std::filesystem::path(root_) / (kPartitionDirectoryPrefix + id)).string();
}

DesktopPartitionRegistry::Entry* DesktopPartitionRegistry::Find(const std::string& id) {
  const auto found = entries_.find(id);
  return found == entries_.end() ? nullptr : &found->second;
}

const DesktopPartitionRegistry::Entry* DesktopPartitionRegistry::Find(const std::string& id) const {
  const auto found = entries_.find(id);
  return found == entries_.end() ? nullptr : &found->second;
}

DesktopPartitionRegistry::Entry* DesktopPartitionRegistry::Acquire(const std::string& id,
                                                                   bool persistent) {
  if (Entry* existing = Find(id)) return existing;

  CefRequestContextSettings settings;
  const bool on_disk = persistent && !root_.empty();
  if (on_disk) {
    std::error_code error;
    std::filesystem::create_directories(DirectoryFor(id), error);
    if (error) return nullptr;
    CefString(&settings.cache_path) = DirectoryFor(id);
  }
  // An empty cache_path is CEF's in-memory context, which is exactly what a
  // non-persistent partition needs: the data never reaches the disk.
  CefRefPtr<PartitionContextHandler> handler = new PartitionContextHandler();
  CefRefPtr<CefRequestContext> context = CefRequestContext::CreateContext(settings, handler);
  if (!context) return nullptr;

  Entry entry;
  entry.id = id;
  entry.context = context;
  entry.handler = handler;
  entry.persistent = on_disk;
  auto inserted = entries_.emplace(id, std::move(entry));
  return &inserted.first->second;
}

void DesktopPartitionRegistry::Erase(const std::string& id) {
  entries_.erase(id);
}

void DesktopPartitionRegistry::Clear() {
  entries_.clear();
}

std::vector<DesktopPartitionRegistry::Entry*> DesktopPartitionRegistry::Entries() {
  std::vector<Entry*> all;
  all.reserve(entries_.size());
  for (auto& item : entries_) all.push_back(&item.second);
  return all;
}

bool DesktopPartitionRegistry::RemoveStorage(const std::string& root, const std::string& id) {
  if (root.empty()) return true;
  const std::filesystem::path directory =
      std::filesystem::path(root) / (kPartitionDirectoryPrefix + id);
  std::error_code error;
  if (!std::filesystem::exists(directory, error)) return true;
  std::filesystem::remove_all(directory, error);
  if (!error) return true;

  std::error_code trash_error;
  std::filesystem::create_directories(TrashRoot(root), trash_error);
  if (trash_error) return false;
  const std::filesystem::path grave =
      TrashRoot(root) / (kPartitionDirectoryPrefix + id + "-" + EpochSuffix());
  std::filesystem::rename(directory, grave, trash_error);
  return !trash_error;
}

void DesktopPartitionRegistry::PurgeTrash(const std::string& root) {
  if (root.empty()) return;
  std::error_code error;
  std::filesystem::remove_all(TrashRoot(root), error);
}

}  // namespace kelpie
