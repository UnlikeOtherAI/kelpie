#include "kelpie/favicon_registry.h"

#include <algorithm>
#include <cctype>
#include <utility>

namespace kelpie {

FaviconRegistry::FaviconRegistry(std::size_t capacity)
    : capacity_(capacity == 0 ? 1 : capacity) {}

std::string FaviconRegistry::NormalizeHost(std::string_view host) {
  std::string normalized(host);
  std::transform(normalized.begin(), normalized.end(), normalized.begin(), [](unsigned char ch) {
    return static_cast<char>(std::tolower(ch));
  });
  return normalized;
}

std::string FaviconRegistry::HostForUrl(std::string_view url) {
  const std::size_t scheme_end = url.find("://");
  if (scheme_end == std::string_view::npos) {
    return std::string();
  }
  std::string_view authority = url.substr(scheme_end + 3);
  const std::size_t authority_end = authority.find_first_of("/?#");
  if (authority_end != std::string_view::npos) {
    authority = authority.substr(0, authority_end);
  }
  // Drop userinfo: `https://user:pass@example.com/` keys on `example.com`.
  const std::size_t at = authority.rfind('@');
  if (at != std::string_view::npos) {
    authority = authority.substr(at + 1);
  }
  if (authority.empty()) {
    return std::string();
  }
  if (authority.front() == '[') {
    // IPv6 literal: keep the brackets, drop any `:port` after the closing one.
    const std::size_t close = authority.find(']');
    if (close == std::string_view::npos) {
      return std::string();
    }
    return NormalizeHost(authority.substr(0, close + 1));
  }
  const std::size_t colon = authority.find(':');
  if (colon != std::string_view::npos) {
    authority = authority.substr(0, colon);
  }
  return NormalizeHost(authority);
}

void FaviconRegistry::TouchLocked(
    std::unordered_map<std::string, std::list<Entry>::iterator>::iterator it) {
  entries_.splice(entries_.begin(), entries_, it->second);
}

bool FaviconRegistry::Store(const std::string& host, std::string png_base64) {
  const std::string key = NormalizeHost(host);
  if (key.empty() || png_base64.empty()) {
    return false;
  }

  std::lock_guard<std::mutex> lock(mutex_);
  const auto existing = index_.find(key);
  if (existing != index_.end()) {
    existing->second->png_base64 = std::move(png_base64);
    TouchLocked(existing);
    return true;
  }

  entries_.push_front(Entry{key, std::move(png_base64)});
  index_.emplace(key, entries_.begin());
  while (entries_.size() > capacity_) {
    index_.erase(entries_.back().host);
    entries_.pop_back();
  }
  return true;
}

std::optional<std::string> FaviconRegistry::Lookup(const std::string& host) {
  const std::string key = NormalizeHost(host);
  std::lock_guard<std::mutex> lock(mutex_);
  const auto it = index_.find(key);
  if (it == index_.end()) {
    return std::nullopt;
  }
  TouchLocked(it);
  return entries_.front().png_base64;
}

std::optional<std::string> FaviconRegistry::Peek(const std::string& host) const {
  const std::string key = NormalizeHost(host);
  std::lock_guard<std::mutex> lock(mutex_);
  const auto it = index_.find(key);
  if (it == index_.end()) {
    return std::nullopt;
  }
  return it->second->png_base64;
}

void FaviconRegistry::Clear() {
  std::lock_guard<std::mutex> lock(mutex_);
  index_.clear();
  entries_.clear();
}

std::size_t FaviconRegistry::size() const {
  std::lock_guard<std::mutex> lock(mutex_);
  return entries_.size();
}

std::vector<std::string> FaviconRegistry::HostsMostRecentFirst() const {
  std::lock_guard<std::mutex> lock(mutex_);
  std::vector<std::string> hosts;
  hosts.reserve(entries_.size());
  for (const Entry& entry : entries_) {
    hosts.push_back(entry.host);
  }
  return hosts;
}

}  // namespace kelpie
