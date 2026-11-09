#include "sync_store.h"

namespace kelpie::sync {
namespace {

struct Cursor {
  std::string replica;
  std::uint64_t seq = 0;
};

Cursor ParseCursor(const nlohmann::json& json, const char* what) {
  if (!json.is_object()) throw SyncError{"INVALID_MESSAGE", std::string(what) + " must be an object"};
  const auto replica = json.find("replica");
  const auto seq = json.find("seq");
  std::uint64_t value = 0;
  if (replica == json.end() || !replica->is_string() || seq == json.end() || !ReadUnsigned(*seq, &value)) {
    throw SyncError{"INVALID_MESSAGE", std::string(what) + " needs replica and seq"};
  }
  return Cursor{replica->get<std::string>(), value};
}

}  // namespace

// Forwards the accepted record with the engine's value. The value must hash to
// the accepted one; otherwise this device cannot vouch for it and the page
// stops (only an Android coverage gap can cause this, because a scan runs
// before every page).
std::optional<nlohmann::json> SyncStore::RecordFor(const Entry& entry, const EngineMap& engine) const {
  nlohmann::json record = {
      {"domain", entry.domain}, {"path", entry.path}, {"name", entry.name},
      {"hlc", HlcToJson(entry.hlc)}, {"deleted", entry.deleted},
  };
  if (entry.deleted) return record;
  const auto it = engine.find(entry.Key());
  if (it == engine.end() || ValueHash(it->second.cookie.value) != entry.value_hash) return std::nullopt;
  record["value"] = it->second.cookie.value;
  record["expires"] = entry.expires ? nlohmann::json(*entry.expires) : nlohmann::json(nullptr);
  record["secure"] = entry.secure;
  record["httpOnly"] = entry.http_only;
  record["sameSite"] = entry.same_site;
  return record;
}

SyncStore::Page SyncStore::BuildPage(std::uint64_t after, const EngineMap& engine) const {
  Page page;
  page.cursor = after;
  auto it = by_seq_.upper_bound(after);
  for (; it != by_seq_.end(); ++it) {
    if (page.records.size() >= kPageSize) {
      page.more = true;
      return page;
    }
    const Entry& entry = entries_.at(it->second);
    if (entry.Forwardable()) {
      auto record = RecordFor(entry, engine);
      if (!record) {
        page.incomplete = true;  // never move the cursor past an unsent record
        return page;
      }
      page.records.push_back(std::move(*record));
    }
    page.cursor = it->first;
  }
  page.cursor = std::max(page.cursor, head_);
  return page;
}

nlohmann::json SyncStore::AnswerPull(const nlohmann::json& pull, const nlohmann::json& cookies,
                                     const nlohmann::json& coverage, std::int64_t now) {
  RequireIdle();
  if (!pull.is_object() || pull.value("op", std::string()) != "pull") {
    throw SyncError{"INVALID_MESSAGE", "expected a pull"};
  }
  const auto requester = pull.find("replica");
  if (requester == pull.end() || !requester->is_string()) throw SyncError{"INVALID_MESSAGE", "pull needs replica"};
  const Cursor since = ParseCursor(pull.value("since", nlohmann::json()), "since");
  const std::uint64_t after = since.replica == replica_ ? since.seq : 0;

  nlohmann::json response = {
      {"replica", replica_},
      {"yourWatermark", Watermark(requester->get<std::string>())},
  };
  if (warming_) {
    response.update({{"head", head_}, {"seq", after}, {"more", false}, {"incomplete", false},
                     {"warming", true}, {"records", nlohmann::json::array()}});
    return response;
  }
  const auto engine = ParseEngine(cookies);
  ScanParsed(engine, ParseCoverage(coverage), now);
  Page page = BuildPage(after, engine);
  response.update({{"head", head_}, {"seq", page.cursor}, {"more", page.more},
                   {"incomplete", page.incomplete}, {"warming", false},
                   {"records", std::move(page.records)}});
  return response;
}

nlohmann::json SyncStore::BuildPush(const nlohmann::json& watermark, const nlohmann::json& cookies,
                                    const nlohmann::json& coverage, std::int64_t now) {
  RequireIdle();
  if (warming_) return {{"push", nullptr}};
  const Cursor known = ParseCursor(watermark, "watermark");
  const std::uint64_t after = known.replica == replica_ ? known.seq : 0;
  const auto engine = ParseEngine(cookies);
  ScanParsed(engine, ParseCoverage(coverage), now);
  Page page = BuildPage(after, engine);
  if (page.records.empty()) return {{"push", nullptr}, {"incomplete", page.incomplete}};
  return {{"push",
           {{"op", "push"}, {"replica", replica_}, {"seq", page.cursor}, {"more", page.more},
            {"records", std::move(page.records)}}},
          {"incomplete", page.incomplete}};
}

}  // namespace kelpie::sync
