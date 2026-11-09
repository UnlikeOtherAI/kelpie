#include "kelpie/site_preview_store.h"

#include <algorithm>
#include <cctype>
#include <fstream>
#include <iterator>
#include <system_error>
#include <utility>
#include <vector>

namespace kelpie {
namespace {

constexpr std::string_view kThumbnailExtension = ".jpg";
constexpr std::string_view kFaviconExtension = ".png";
// Long enough for any real host name; short enough that the hex file name stays
// well inside every file system's 255-byte component limit.
constexpr std::size_t kMaxHostLength = 120;

bool IsHostCharacter(char character) {
  return (character >= 'a' && character <= 'z') || (character >= '0' && character <= '9') ||
         character == '.' || character == '-' || character == '_' || character == ':' ||
         character == '[' || character == ']';
}

std::string Normalize(std::string_view host) {
  std::string normalized(host);
  std::transform(normalized.begin(), normalized.end(), normalized.begin(), [](unsigned char ch) {
    return static_cast<char>(std::tolower(ch));
  });
  return normalized;
}

bool IsStorableHost(const std::string& host) {
  return !host.empty() && host.size() <= kMaxHostLength &&
         std::all_of(host.begin(), host.end(), IsHostCharacter);
}

}  // namespace

SitePreviewStore::SitePreviewStore(std::filesystem::path directory, std::size_t capacity)
    : directory_(std::move(directory)), capacity_(capacity == 0 ? 1 : capacity) {
  std::lock_guard<std::mutex> lock(mutex_);
  LoadLocked();
}

std::string SitePreviewStore::KeyForHost(std::string_view host) {
  static constexpr char kDigits[] = "0123456789abcdef";
  const std::string normalized = Normalize(host);
  std::string key;
  key.reserve(normalized.size() * 2);
  for (const unsigned char character : normalized) {
    key.push_back(kDigits[character >> 4U]);
    key.push_back(kDigits[character & 0x0FU]);
  }
  return key;
}

std::optional<std::string> SitePreviewStore::HostForKey(std::string_view key) {
  if (key.empty() || key.size() % 2 != 0 || key.size() > kMaxHostLength * 2) return std::nullopt;
  const auto nibble = [](char character) -> int {
    if (character >= '0' && character <= '9') return character - '0';
    if (character >= 'a' && character <= 'f') return character - 'a' + 10;
    return -1;
  };
  std::string host;
  host.reserve(key.size() / 2);
  for (std::size_t index = 0; index < key.size(); index += 2) {
    const int high = nibble(key[index]);
    const int low = nibble(key[index + 1]);
    if (high < 0 || low < 0) return std::nullopt;
    const char character = static_cast<char>((high << 4) | low);
    if (!IsHostCharacter(character)) return std::nullopt;
    host.push_back(character);
  }
  return host;
}

void SitePreviewStore::LoadLocked() {
  if (directory_.empty()) return;
  std::error_code error;
  std::filesystem::create_directories(directory_, error);
  struct Found {
    std::filesystem::file_time_type written;
    std::string host;
  };
  std::vector<Found> found;
  for (const auto& item : std::filesystem::directory_iterator(directory_, error)) {
    const auto path = item.path();
    const std::string extension = path.extension().string();
    if (extension == ".tmp") {
      // A write interrupted before its rename; the previous file is intact.
      std::filesystem::remove(path, error);
      continue;
    }
    if (extension != kThumbnailExtension && extension != kFaviconExtension) continue;
    const auto host = HostForKey(path.stem().string());
    if (!host || !item.is_regular_file(error)) continue;
    Entry& entry = entries_[*host];
    (extension == kThumbnailExtension ? entry.has_thumbnail : entry.has_favicon) = true;
    found.push_back({item.last_write_time(error), *host});
  }
  // Oldest first, so the most recently written host ends with the highest order
  // and survives eviction longest.
  std::sort(found.begin(), found.end(),
            [](const Found& left, const Found& right) { return left.written < right.written; });
  for (const Found& item : found) {
    Entry& entry = entries_[item.host];
    entry.order = next_order_++;
    if (entry.has_thumbnail) entry.thumbnail_version = entry.order;
  }
  EvictLocked();
}

bool SitePreviewStore::WriteLocked(const std::string& host, std::string_view extension,
                                   const std::string& bytes) {
  if (directory_.empty()) return true;
  const std::string name = KeyForHost(host) + std::string(extension);
  const auto target = directory_ / name;
  const auto temporary = directory_ / (name + ".tmp");
  {
    std::ofstream file(temporary, std::ios::binary | std::ios::trunc);
    if (!file) return false;
    file.write(bytes.data(), static_cast<std::streamsize>(bytes.size()));
    if (!file) return false;
  }
  std::error_code error;
  std::filesystem::rename(temporary, target, error);
  if (error) {
    std::filesystem::remove(temporary, error);
    return false;
  }
  return true;
}

std::optional<std::string> SitePreviewStore::ReadLocked(const std::string& host,
                                                        std::string_view extension) const {
  const auto entry = entries_.find(host);
  if (entry == entries_.end()) return std::nullopt;
  const bool thumbnail = extension == kThumbnailExtension;
  if (!(thumbnail ? entry->second.has_thumbnail : entry->second.has_favicon)) return std::nullopt;
  if (directory_.empty()) return thumbnail ? entry->second.thumbnail : entry->second.favicon;
  std::ifstream file(directory_ / (KeyForHost(host) + std::string(extension)), std::ios::binary);
  if (!file) return std::nullopt;
  return std::string(std::istreambuf_iterator<char>(file), std::istreambuf_iterator<char>());
}

void SitePreviewStore::EraseLocked(const std::string& host) {
  if (!directory_.empty()) {
    std::error_code error;
    const std::string key = KeyForHost(host);
    std::filesystem::remove(directory_ / (key + std::string(kThumbnailExtension)), error);
    std::filesystem::remove(directory_ / (key + std::string(kFaviconExtension)), error);
  }
  entries_.erase(host);
}

void SitePreviewStore::EvictLocked() {
  while (entries_.size() > capacity_) {
    const auto oldest = std::min_element(entries_.begin(), entries_.end(), [](const auto& left, const auto& right) {
      return left.second.order < right.second.order;
    });
    EraseLocked(std::string(oldest->first));
  }
}

bool SitePreviewStore::StoreThumbnail(const std::string& host, std::string jpeg) {
  const std::string key = Normalize(host);
  if (!IsStorableHost(key) || jpeg.empty()) return false;
  std::lock_guard<std::mutex> lock(mutex_);
  if (!WriteLocked(key, kThumbnailExtension, jpeg)) return false;
  Entry& entry = entries_[key];
  entry.order = next_order_++;
  entry.thumbnail_version = entry.order;
  entry.has_thumbnail = true;
  if (directory_.empty()) entry.thumbnail = std::move(jpeg);
  EvictLocked();
  return true;
}

bool SitePreviewStore::StoreFavicon(const std::string& host, std::string png) {
  const std::string key = Normalize(host);
  if (!IsStorableHost(key) || png.empty()) return false;
  std::lock_guard<std::mutex> lock(mutex_);
  if (!WriteLocked(key, kFaviconExtension, png)) return false;
  Entry& entry = entries_[key];
  if (entry.order == 0) entry.order = next_order_++;
  entry.has_favicon = true;
  if (directory_.empty()) entry.favicon = std::move(png);
  EvictLocked();
  return true;
}

std::optional<std::string> SitePreviewStore::Thumbnail(const std::string& host) const {
  std::lock_guard<std::mutex> lock(mutex_);
  return ReadLocked(Normalize(host), kThumbnailExtension);
}

std::optional<std::string> SitePreviewStore::Favicon(const std::string& host) const {
  std::lock_guard<std::mutex> lock(mutex_);
  return ReadLocked(Normalize(host), kFaviconExtension);
}

std::optional<std::uint64_t> SitePreviewStore::ThumbnailVersion(const std::string& host) const {
  std::lock_guard<std::mutex> lock(mutex_);
  const auto entry = entries_.find(Normalize(host));
  if (entry == entries_.end() || !entry->second.has_thumbnail) return std::nullopt;
  return entry->second.thumbnail_version;
}

void SitePreviewStore::RetainOnly(const std::unordered_set<std::string>& hosts) {
  std::lock_guard<std::mutex> lock(mutex_);
  std::vector<std::string> stale;
  for (const auto& [host, entry] : entries_) {
    if (hosts.find(host) == hosts.end()) stale.push_back(host);
  }
  for (const std::string& host : stale) EraseLocked(host);
}

std::size_t SitePreviewStore::size() const {
  std::lock_guard<std::mutex> lock(mutex_);
  return entries_.size();
}

}  // namespace kelpie
