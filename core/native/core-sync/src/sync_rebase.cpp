#include "sync_store.h"

namespace kelpie::sync {

// A renderer switch moves the default store to an engine that may normalise,
// refuse or already hold different cookies. None of that is a local edit, so
// the new engine's state becomes `observed` and versions stay as they are.
nlohmann::json SyncStore::Rebase(const nlohmann::json& cookies, const nlohmann::json& coverage, std::int64_t) {
  RequireIdle();
  const auto engine = ParseEngine(cookies);
  const auto parsed_coverage = ParseCoverage(coverage);
  std::size_t adopted = 0;

  for (const auto& [key, engine_cookie] : engine) {
    if (engine_cookie.ambiguous) continue;
    const auto it = entries_.find(key);
    if (it == entries_.end()) {
      // Only this engine had it: adopt with the zero version so any peer wins.
      Entry entry;
      entry.domain = engine_cookie.cookie.domain;
      entry.path = engine_cookie.cookie.path;
      entry.name = engine_cookie.cookie.name;
      entry.hlc = Hlc{0, 0, replica_};
      AcceptCookie(&entry, engine_cookie.cookie);
      entry.observed = engine_cookie.fingerprint;
      auto& stored = entries_[key] = std::move(entry);
      Touch(&stored);
      ++adopted;
      continue;
    }
    Entry& entry = it->second;
    entry.observed = engine_cookie.fingerprint;
    if (entry.local_only) continue;
    // A tombstone whose cookie this engine still holds, or a live record whose
    // value this engine does not hold, cannot be vouched for by this device.
    entry.unapplied = entry.deleted || ValueHash(engine_cookie.cookie.value) != entry.value_hash;
  }

  std::vector<std::string> drops;
  for (auto& [key, entry] : entries_) {
    if (engine.count(key) != 0 || !parsed_coverage.Covers(entry)) continue;
    if (entry.local_only) {
      drops.push_back(key);
      continue;
    }
    entry.observed = kObservedAbsent;
    entry.unapplied = !entry.deleted;  // a live record this engine lacks
  }
  for (const auto& key : drops) Erase(key);

  Persist();
  return {{"adopted", adopted}, {"head", head_}};
}

}  // namespace kelpie::sync
