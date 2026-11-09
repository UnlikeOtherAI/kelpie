#include <algorithm>
#include <cctype>

#include "sync_store.h"

namespace kelpie::sync {
namespace {

constexpr std::size_t kMaxRecordsPerMerge = 2 * kPageSize;

std::string Lower(std::string text) {
  std::transform(text.begin(), text.end(), text.begin(),
                 [](unsigned char c) { return static_cast<char>(std::tolower(c)); });
  return text;
}

}  // namespace

// Validates one remote record and decides whether it beats the local entry.
// Returns nullopt for records to ignore and sets *invalid for malformed ones,
// which are counted in status rather than failing the whole page.
std::optional<SyncStore::PlannedOp> SyncStore::PlanRecord(const nlohmann::json& record, bool* invalid) {
  *invalid = true;
  if (!record.is_object()) return std::nullopt;
  const auto hlc_field = record.find("hlc");
  if (hlc_field == record.end()) return std::nullopt;
  const auto hlc = HlcFromJson(*hlc_field);
  const auto deleted = record.find("deleted");
  if (!hlc || deleted == record.end() || !deleted->is_boolean()) return std::nullopt;

  PlannedOp op;
  op.hlc = *hlc;
  op.remove = deleted->get<bool>();
  if (op.remove) {
    // A tombstone carries only its identity. Parse it through the cookie rules
    // with placeholder attributes so it gets the same canonical key.
    nlohmann::json shape = {{"domain", record.value("domain", nlohmann::json())},
                            {"path", record.value("path", nlohmann::json())},
                            {"name", record.value("name", nlohmann::json())},
                            {"value", ""}, {"sameSite", "Unspecified"}};
    if (!shape["domain"].is_string() || !shape["path"].is_string() || !shape["name"].is_string()) {
      return std::nullopt;
    }
    shape["domain"] = Lower(shape["domain"].get<std::string>());
    const auto parsed = ParseCookie(shape);
    if (!parsed.cookie) return std::nullopt;
    op.domain = parsed.cookie->domain;
    op.path = parsed.cookie->path;
    op.name = parsed.cookie->name;
  } else {
    auto parsed = ParseCookie(record);
    if (!parsed.cookie) return std::nullopt;
    op.domain = parsed.cookie->domain;
    op.path = parsed.cookie->path;
    op.name = parsed.cookie->name;
    op.cookie = std::move(parsed.cookie);
  }
  op.key = CookieKey(op.domain, op.path, op.name);
  *invalid = false;

  const auto it = entries_.find(op.key);
  if (it != entries_.end() && !it->second.local_only && !(op.hlc > it->second.hlc)) return std::nullopt;
  return op;
}

bool SyncStore::WithinCaps(const Cookie& cookie, std::map<std::string, std::size_t>* host_counts,
                           std::size_t* live_count) const {
  const auto it = entries_.find(CookieKey(cookie));
  if (it != entries_.end() && it->second.Live()) return true;  // replaces an existing cookie
  std::size_t& host_count = (*host_counts)[cookie.host()];
  if (host_count >= kMaxCookiesPerHost || *live_count >= kMaxLiveEntries) return false;
  ++host_count;
  ++*live_count;
  return true;
}

nlohmann::json SyncStore::PlanMerge(const nlohmann::json& records, const nlohmann::json& source, std::int64_t) {
  RequireIdle();
  if (!records.is_array() || records.size() > kMaxRecordsPerMerge) {
    throw SyncError{"INVALID_MESSAGE", "records must be an array of at most 1000"};
  }
  PendingMerge pending;
  if (source.is_object()) {
    const auto replica = source.find("replica");
    const auto seq = source.find("seq");
    if (replica != source.end() && replica->is_string() && seq != source.end() && seq->is_number_unsigned()) {
      pending.source_replica = replica->get<std::string>();
      pending.source_seq = seq->get<std::uint64_t>();
    }
  }

  std::map<std::string, std::size_t> host_counts;
  std::size_t live_count = 0;
  for (const auto& [key, entry] : entries_) {
    if (!entry.Live()) continue;
    ++live_count;
    ++host_counts[entry.Shape().host()];
  }

  std::map<std::string, std::size_t> index_by_key;
  std::size_t ignored = 0, invalid = 0;
  for (const auto& record : records) {
    bool malformed = false;
    auto op = PlanRecord(record, &malformed);
    if (!op) {
      malformed ? ++invalid : ++ignored;
      continue;
    }
    if (op->cookie && !WithinCaps(*op->cookie, &host_counts, &live_count)) {
      ++skipped_;
      continue;
    }
    const auto existing = index_by_key.find(op->key);
    if (existing != index_by_key.end()) {
      if (op->hlc > pending.ops[existing->second].hlc) pending.ops[existing->second] = std::move(*op);
      continue;
    }
    index_by_key[op->key] = pending.ops.size();
    pending.ops.push_back(std::move(*op));
  }
  skipped_ += invalid;

  nlohmann::json ops = nlohmann::json::array();
  for (std::size_t i = 0; i < pending.ops.size(); ++i) {
    const auto& op = pending.ops[i];
    nlohmann::json cookie = op.cookie ? CookieToJson(*op.cookie)
                                      : nlohmann::json{{"domain", op.domain}, {"path", op.path}, {"name", op.name}};
    ops.push_back({{"id", i}, {"op", op.remove ? "delete" : "set"}, {"cookie", std::move(cookie)}});
  }
  merge_ = std::move(pending);
  return {{"ops", std::move(ops)}, {"ignored", ignored}, {"invalid", invalid}};
}

// Records the outcome of one engine write. The entry always takes the remote
// version; `observed` records what the engine really holds, so a refused or
// reshaped write can never come back as a fresh local change.
void SyncStore::CommitOp(const PlannedOp& op, bool ok, const EngineMap& readback) {
  Entry& entry = entries_[op.key];
  entry.domain = op.domain;
  entry.path = op.path;
  entry.name = op.name;
  entry.hlc = op.hlc;
  entry.local_only = false;
  const auto found = readback.find(op.key);

  if (op.remove) {
    entry.deleted = true;
    entry.value_hash.clear();
    entry.unapplied = found != readback.end();
    entry.observed = entry.unapplied ? found->second.fingerprint : kObservedAbsent;
    Touch(&entry);
    return;
  }

  entry.deleted = false;
  AcceptCookie(&entry, *op.cookie);
  const bool same_value = found != readback.end() && ValueHash(found->second.cookie.value) == entry.value_hash;
  entry.unapplied = !(ok && same_value);
  entry.observed = found != readback.end() ? found->second.fingerprint : kObservedAbsent;
  Touch(&entry);

  if (found != readback.end()) return;
  // The engine stored the cookie under another domain or path (for example
  // host-only instead of a domain cookie). Track that variant as local-only so
  // it is never forwarded and cannot start a delete-and-recreate loop.
  for (const auto& [variant_key, variant] : readback) {
    if (variant_key == op.key || entries_.count(variant_key) != 0) continue;
    if (variant.cookie.name != op.name) continue;
    Entry shadow;
    shadow.domain = variant.cookie.domain;
    shadow.path = variant.cookie.path;
    shadow.name = variant.cookie.name;
    shadow.hlc = op.hlc;
    AcceptCookie(&shadow, variant.cookie);
    shadow.observed = variant.fingerprint;
    shadow.local_only = true;
    auto& stored = entries_[variant_key] = std::move(shadow);
    Touch(&stored);
  }
}

nlohmann::json SyncStore::CommitMerge(const nlohmann::json& results) {
  if (!merge_) throw SyncError{"NO_MERGE", "no merge transaction is open"};
  PendingMerge pending = std::move(*merge_);
  merge_.reset();
  if (!results.is_array()) throw SyncError{"INVALID_RESULTS", "results must be an array"};

  // Validate every result before touching any entry, so a bad call leaves the
  // store exactly as it was.
  std::map<std::size_t, const nlohmann::json*> by_id;
  for (const auto& result : results) {
    if (!result.is_object() || !result.contains("id") || !result["id"].is_number_unsigned()) {
      throw SyncError{"INVALID_RESULTS", "every result needs an id"};
    }
    by_id[result["id"].get<std::size_t>()] = &result;
  }
  std::vector<std::pair<bool, EngineMap>> outcomes;
  outcomes.reserve(pending.ops.size());
  for (std::size_t i = 0; i < pending.ops.size(); ++i) {
    const auto it = by_id.find(i);
    if (it == by_id.end()) throw SyncError{"INCOMPLETE_RESULTS", "every planned op needs a result"};
    const auto& result = *it->second;
    outcomes.emplace_back(result.value("ok", false),
                          ParseEngine(result.value("readback", nlohmann::json::array())));
  }
  for (std::size_t i = 0; i < pending.ops.size(); ++i) {
    CommitOp(pending.ops[i], outcomes[i].first, outcomes[i].second);
    Observe(pending.ops[i].hlc);
  }
  if (pending.source_replica) {
    auto& watermark = watermarks_[*pending.source_replica];
    watermark = std::max(watermark, pending.source_seq);
  }
  EnforceTombstoneCap();
  Persist();
  return {{"applied", pending.ops.size()}, {"head", head_}};
}

}  // namespace kelpie::sync
