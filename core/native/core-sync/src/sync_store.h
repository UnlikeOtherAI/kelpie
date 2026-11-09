#pragma once

#include <cstdint>
#include <map>
#include <memory>
#include <optional>
#include <string>
#include <vector>

#include <nlohmann/json.hpp>

#include "sync_entry.h"

namespace kelpie::sync {

// Limits shared by every platform. See docs/plans/2026-11-09-p2p-cookie-sync.md.
inline constexpr std::size_t kPageSize = 500;
// Chromium evicts beyond 180 cookies per registrable domain, so the synced set
// stays under that for every site, counted the same way (see SiteOf).
inline constexpr std::size_t kMaxCookiesPerSite = 150;
inline constexpr std::size_t kMaxLiveEntries = 3000;
inline constexpr std::size_t kMaxTombstones = 20000;
inline constexpr std::size_t kPurgeMinimum = 20;
inline constexpr double kPurgeFraction = 0.25;

// Thrown for caller errors; the C API turns it into {"error": code}.
struct SyncError {
  std::string code;
  std::string message;
};

// The replication state of one device's default cookie store for one UOA
// subject. Not thread-safe: every call for one store must run on one serial
// executor, and a merge transaction (plan → engine writes → commit) holds it.
class SyncStore {
 public:
  struct Options {
    std::string subject;
    std::string replica;
    bool launch = false;  // first open in this process
    std::int64_t now_millis = 0;
  };

  // Opens or creates the file at `path`. Throws SyncError on I/O failure.
  static std::unique_ptr<SyncStore> Open(const std::string& path, const Options& options);

  nlohmann::json Status() const;
  void FinishWarmup() { warming_ = false; }

  nlohmann::json Scan(const nlohmann::json& cookies, const nlohmann::json& coverage, std::int64_t now);
  // The default store moved to another engine (macOS renderer switch). Adopt
  // what the new engine holds as observed state: stamp nothing, tombstone nothing.
  nlohmann::json Rebase(const nlohmann::json& cookies, const nlohmann::json& coverage, std::int64_t now);
  nlohmann::json AnswerPull(const nlohmann::json& pull, const nlohmann::json& cookies,
                            const nlohmann::json& coverage, std::int64_t now);
  nlohmann::json BuildPush(const nlohmann::json& watermark, const nlohmann::json& cookies,
                           const nlohmann::json& coverage, std::int64_t now);

  nlohmann::json PlanMerge(const nlohmann::json& records, const nlohmann::json& source, std::int64_t now);
  nlohmann::json CommitMerge(const nlohmann::json& results);
  void AbortMerge() { merge_.reset(); }

  nlohmann::json Watermark(const std::string& replica) const;

 private:
  enum class Adoption { kNormal, kZeroVersion, kForeign };

  // What a scan actually observed: the whole store, or the cookies that the
  // listed URLs would return. URLs are indexed by every domain suffix of their
  // host so an entry finds its candidate URLs without a full sweep.
  struct Coverage {
    bool all = false;
    std::map<std::string, std::vector<UrlParts>> by_host_suffix;
    bool Covers(const Entry& entry) const;
  };

  struct EngineCookie {
    Cookie cookie;
    std::string fingerprint;
    // The engine reported this key more than once (Chromium lists every CHIPS
    // partition of a cookie without marking it). Its value cannot be known, so
    // the key is neither synced nor treated as deleted.
    bool ambiguous = false;
  };
  using EngineMap = std::map<std::string, EngineCookie>;

  struct PlannedOp {
    std::string key;
    std::string domain;
    std::string path;
    std::string name;
    bool remove = false;
    Hlc hlc;
    std::optional<Cookie> cookie;  // set only
  };
  struct PendingMerge {
    std::vector<PlannedOp> ops;
    std::optional<std::string> source_replica;
    std::uint64_t source_seq = 0;
  };

  struct Page {
    nlohmann::json records = nlohmann::json::array();
    std::uint64_t cursor = 0;
    bool more = false;
    bool incomplete = false;
  };

  SyncStore() = default;

  // Persistence (sync_store.cpp).
  void Load(const Options& options);
  void Persist() const;
  void Renumber();
  void Touch(Entry* entry);
  void Erase(const std::string& key);
  Hlc Stamp(std::int64_t now);
  void Observe(const Hlc& remote);
  void RequireIdle() const;

  // Scan (sync_scan.cpp).
  static Coverage ParseCoverage(const nlohmann::json& coverage);
  static EngineMap ParseEngine(const nlohmann::json& cookies);
  nlohmann::json ScanParsed(const EngineMap& engine, const Coverage& coverage, std::int64_t now);
  int ScanPresent(const std::string& key, const EngineCookie& cookie, std::int64_t now);
  int ScanAbsent(const EngineMap& engine, const Coverage& coverage, std::int64_t now, bool* purge);
  void EnforceTombstoneCap();

  // Feed (sync_feed.cpp).
  Page BuildPage(std::uint64_t after, const EngineMap& engine) const;
  std::optional<nlohmann::json> RecordFor(const Entry& entry, const EngineMap& engine) const;

  // Merge (sync_merge.cpp).
  std::optional<PlannedOp> PlanRecord(const nlohmann::json& record, bool* invalid);
  bool WithinCaps(const Cookie& cookie, std::map<std::string, std::size_t>* host_counts,
                  std::size_t* live_count) const;
  void CommitOp(const PlannedOp& op, bool ok, const EngineMap& readback);

  std::string path_;
  std::string subject_;
  std::string replica_;
  Hlc last_hlc_;
  std::map<std::string, Entry> entries_;
  std::map<std::uint64_t, std::string> by_seq_;
  std::uint64_t head_ = 0;
  Adoption adoption_ = Adoption::kNormal;
  bool warming_ = false;
  bool first_scan_after_launch_ = false;
  std::optional<PendingMerge> merge_;
  std::map<std::string, std::uint64_t> watermarks_;
  std::uint64_t skipped_ = 0;
  std::int64_t last_purge_at_ = 0;
};

}  // namespace kelpie::sync
