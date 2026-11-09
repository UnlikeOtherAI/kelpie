#include <algorithm>

#include "sync_store.h"

namespace kelpie::sync {
namespace {

constexpr std::size_t kMaxCoverageUrls = 50000;
constexpr std::size_t kMaxEngineCookies = 20000;

enum Effect { kNoEffect = 0, kPersistOnly = 1, kFeedChange = 2 };

}  // namespace

bool SyncStore::Coverage::Covers(const Entry& entry) const {
  if (all) return true;
  const Cookie shape = entry.Shape();
  const auto it = by_host_suffix.find(shape.host());
  if (it == by_host_suffix.end()) return false;
  return std::any_of(it->second.begin(), it->second.end(),
                     [&](const UrlParts& url) { return CookieMatchesUrl(shape, url); });
}

SyncStore::Coverage SyncStore::ParseCoverage(const nlohmann::json& coverage) {
  Coverage parsed;
  if (coverage.is_object() && coverage.value("all", false) == true) {
    parsed.all = true;
    return parsed;
  }
  const auto urls = coverage.is_object() ? coverage.find("urls") : coverage.end();
  if (!coverage.is_object() || urls == coverage.end() || !urls->is_array() || urls->size() > kMaxCoverageUrls) {
    throw SyncError{"INVALID_COVERAGE", "coverage must be {\"all\":true} or {\"urls\":[…]}"};
  }
  for (const auto& url : *urls) {
    if (!url.is_string()) throw SyncError{"INVALID_COVERAGE", "coverage urls must be strings"};
    const auto parts = ParseUrl(url.get<std::string>());
    if (!parts) throw SyncError{"INVALID_COVERAGE", "coverage url is not absolute"};
    // Every suffix of the host at a label boundary: a.b.example.com, b.example.com, example.com, com.
    std::string host = parts->host;
    while (true) {
      parsed.by_host_suffix[host].push_back(*parts);
      const auto dot = host.find('.');
      if (dot == std::string::npos) break;
      host = host.substr(dot + 1);
    }
  }
  return parsed;
}

SyncStore::EngineMap SyncStore::ParseEngine(const nlohmann::json& cookies) {
  if (!cookies.is_array() || cookies.size() > kMaxEngineCookies) {
    throw SyncError{"INVALID_COOKIES", "cookies must be an array"};
  }
  EngineMap engine;
  for (const auto& json : cookies) {
    auto parsed = ParseCookie(json);
    if (!parsed.cookie) continue;  // not syncable: loopback, partitioned, oversized or undescribable
    const std::string key = CookieKey(*parsed.cookie);
    const std::string fingerprint = CookieFingerprint(*parsed.cookie);
    const auto existing = engine.find(key);
    if (existing != engine.end()) {
      existing->second.ambiguous = true;
      continue;
    }
    engine[key] = EngineCookie{std::move(*parsed.cookie), fingerprint};
  }
  return engine;
}

nlohmann::json SyncStore::Scan(const nlohmann::json& cookies, const nlohmann::json& coverage, std::int64_t now) {
  RequireIdle();
  if (warming_) return {{"deferred", true}};
  const auto parsed_coverage = ParseCoverage(coverage);
  const auto engine = ParseEngine(cookies);
  return ScanParsed(engine, parsed_coverage, now);
}

nlohmann::json SyncStore::ScanParsed(const EngineMap& engine, const Coverage& coverage, std::int64_t now) {
  const std::uint64_t head_before = head_;
  int effect = kNoEffect;
  for (const auto& [key, cookie] : engine) effect = std::max<int>(effect, ScanPresent(key, cookie, now));
  bool purge = false;
  effect = std::max<int>(effect, ScanAbsent(engine, coverage, now, &purge));

  const bool was_first = adoption_ != Adoption::kNormal || first_scan_after_launch_;
  adoption_ = Adoption::kNormal;
  first_scan_after_launch_ = false;
  EnforceTombstoneCap();
  if (effect != kNoEffect || was_first) Persist();
  return {{"changed", head_ - head_before}, {"head", head_}, {"purge", purge}};
}

// Returns an Effect. A cookie with no entry is new; a fingerprint that differs
// from `observed` is a genuine engine change, because `observed` always holds
// the engine's own read-back after a remote write.
int SyncStore::ScanPresent(const std::string& key, const EngineCookie& engine_cookie, std::int64_t now) {
  if (engine_cookie.ambiguous) return kNoEffect;
  const Cookie& cookie = engine_cookie.cookie;
  const auto it = entries_.find(key);
  if (it == entries_.end()) {
    Entry entry;
    entry.domain = cookie.domain;
    entry.path = cookie.path;
    entry.name = cookie.name;
    AcceptCookie(&entry, cookie);
    entry.observed = engine_cookie.fingerprint;
    if (adoption_ == Adoption::kForeign) {
      entry.local_only = true;
      entry.hlc = Hlc{0, 0, replica_};
    } else if (adoption_ == Adoption::kZeroVersion || first_scan_after_launch_) {
      entry.hlc = Hlc{0, 0, replica_};  // any real peer version wins
    } else {
      entry.hlc = Stamp(now);
    }
    auto& stored = entries_[key] = std::move(entry);
    Touch(&stored);
    return kFeedChange;
  }

  Entry& entry = it->second;
  if (entry.observed == engine_cookie.fingerprint) return kNoEffect;
  if (entry.local_only) {
    AcceptCookie(&entry, cookie);
    entry.observed = engine_cookie.fingerprint;
    return kPersistOnly;
  }
  if (entry.unapplied && !entry.deleted && ValueHash(cookie.value) == entry.value_hash) {
    // The engine now holds the accepted value — a recovered read, a restored
    // session cookie or a renderer switch, not a local edit. Adopt it without a
    // new version, so a glitch can never re-publish old values over newer ones.
    entry.observed = engine_cookie.fingerprint;
    entry.unapplied = false;
    Touch(&entry);
    return kFeedChange;
  }
  entry.hlc = Stamp(now);
  entry.deleted = false;
  entry.unapplied = false;
  AcceptCookie(&entry, cookie);
  entry.observed = engine_cookie.fingerprint;
  Touch(&entry);
  return kFeedChange;
}

int SyncStore::ScanAbsent(const EngineMap& engine, const Coverage& coverage, std::int64_t now, bool* purge) {
  int effect = kNoEffect;
  std::size_t covered_live = 0;
  std::vector<std::string> candidates;
  std::vector<std::string> drops;
  std::vector<std::string> unknown;  // absent for a reason other than a deletion
  const std::int64_t now_seconds = now / 1000;

  for (auto& [key, entry] : entries_) {
    if (!coverage.Covers(entry)) continue;
    if (entry.Live()) ++covered_live;
    if (engine.count(key) != 0 || entry.observed == kObservedAbsent) continue;
    if (entry.local_only) {
      drops.push_back(key);
    } else if (entry.deleted) {
      entry.observed = kObservedAbsent;  // an earlier refused delete has now happened
      entry.unapplied = false;
      effect = std::max<int>(effect, kPersistOnly);
    } else if (entry.expires && *entry.expires <= now_seconds) {
      drops.push_back(key);  // expired everywhere; no deletion to announce
    } else if (first_scan_after_launch_) {
      unknown.push_back(key);  // the store may not be fully loaded yet
    } else {
      candidates.push_back(key);
    }
  }

  const bool is_purge = candidates.size() > kPurgeMinimum &&
                        static_cast<double>(candidates.size()) > kPurgeFraction * static_cast<double>(covered_live);
  if (is_purge) {
    // An eviction, purge, clear-all or a failed engine read, not a logout:
    // announce nothing.
    *purge = true;
    last_purge_at_ = now;
    unknown.insert(unknown.end(), candidates.begin(), candidates.end());
    candidates.clear();
  }
  for (const auto& key : unknown) {
    // Keep the version so the same value reappearing is not a new edit, and a
    // peer's equal version can put the cookie back (see PlanRecord).
    Entry& entry = entries_.at(key);
    entry.observed = kObservedAbsent;
    entry.unapplied = true;
    effect = std::max<int>(effect, kPersistOnly);
  }
  for (const auto& key : candidates) {
    Entry& entry = entries_.at(key);
    entry.deleted = true;
    entry.unapplied = false;
    entry.value_hash.clear();
    entry.observed = kObservedAbsent;
    entry.hlc = Stamp(now);
    Touch(&entry);
    effect = kFeedChange;
  }
  for (const auto& key : drops) {
    Erase(key);
    effect = std::max<int>(effect, kPersistOnly);
  }
  return effect;
}

void SyncStore::EnforceTombstoneCap() {
  std::vector<const Entry*> tombstones;
  for (const auto& [key, entry] : entries_) {
    if (entry.deleted) tombstones.push_back(&entry);
  }
  if (tombstones.size() <= kMaxTombstones) return;
  std::sort(tombstones.begin(), tombstones.end(),
            [](const Entry* a, const Entry* b) { return a->hlc < b->hlc; });
  std::vector<std::string> doomed;
  for (std::size_t i = 0; i < tombstones.size() - kMaxTombstones; ++i) doomed.push_back(tombstones[i]->Key());
  for (const auto& key : doomed) Erase(key);
}

}  // namespace kelpie::sync
