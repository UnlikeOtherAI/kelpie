#include "sync_entry.h"

#include "sha256.h"

namespace kelpie::sync {
namespace {

constexpr std::size_t kMaxReplicaLength = 64;

bool ReadString(const nlohmann::json& json, const char* field, std::string* out) {
  const auto it = json.find(field);
  if (it == json.end() || !it->is_string()) return false;
  *out = it->get<std::string>();
  return true;
}

bool ReadBool(const nlohmann::json& json, const char* field, bool* out) {
  const auto it = json.find(field);
  if (it == json.end()) return true;
  if (!it->is_boolean()) return false;
  *out = it->get<bool>();
  return true;
}

}  // namespace

nlohmann::json HlcToJson(const Hlc& hlc) {
  return nlohmann::json::array({hlc.wall, hlc.counter, hlc.replica});
}

std::optional<Hlc> HlcFromJson(const nlohmann::json& json) {
  if (!json.is_array() || json.size() != 3 || !json[0].is_number_integer() ||
      !json[1].is_number_integer() || !json[2].is_string()) {
    return std::nullopt;
  }
  Hlc hlc{json[0].get<std::int64_t>(), json[1].get<std::int64_t>(), json[2].get<std::string>()};
  if (hlc.wall < 0 || hlc.counter < 0 || hlc.replica.empty() || hlc.replica.size() > kMaxReplicaLength) {
    return std::nullopt;
  }
  return hlc;
}

Cookie Entry::Shape() const {
  Cookie cookie;
  cookie.domain = domain;
  cookie.path = path;
  cookie.name = name;
  cookie.secure = secure;
  return cookie;
}

void AcceptCookie(Entry* entry, const Cookie& cookie) {
  entry->expires = cookie.expires;
  entry->secure = cookie.secure;
  entry->http_only = cookie.http_only;
  entry->same_site = cookie.same_site;
  entry->value_hash = ValueHash(cookie.value);
}

std::string ValueHash(const std::string& value) {
  return Hex(Sha256::Hash(value));
}

nlohmann::json EntryToStoredJson(const Entry& entry) {
  nlohmann::json json = {
      {"d", entry.domain}, {"p", entry.path}, {"n", entry.name}, {"v", HlcToJson(entry.hlc)},
      {"o", entry.observed},
  };
  if (entry.deleted) json["del"] = true;
  if (entry.unapplied) json["ua"] = true;
  if (entry.local_only) json["lo"] = true;
  if (!entry.deleted) {
    json["x"] = entry.expires ? nlohmann::json(*entry.expires) : nlohmann::json(nullptr);
    json["s"] = entry.secure;
    json["h"] = entry.http_only;
    json["ss"] = entry.same_site;
    json["vh"] = entry.value_hash;
  }
  return json;
}

std::optional<Entry> EntryFromStoredJson(const nlohmann::json& json) {
  if (!json.is_object()) return std::nullopt;
  Entry entry;
  if (!ReadString(json, "d", &entry.domain) || !ReadString(json, "p", &entry.path) ||
      !ReadString(json, "n", &entry.name) || !ReadString(json, "o", &entry.observed)) {
    return std::nullopt;
  }
  const auto version = json.find("v");
  if (version == json.end()) return std::nullopt;
  const auto hlc = HlcFromJson(*version);
  if (!hlc) return std::nullopt;
  entry.hlc = *hlc;
  if (!ReadBool(json, "del", &entry.deleted) || !ReadBool(json, "ua", &entry.unapplied) ||
      !ReadBool(json, "lo", &entry.local_only)) {
    return std::nullopt;
  }
  if (!entry.deleted) {
    if (const auto it = json.find("x"); it != json.end() && !it->is_null()) {
      if (!it->is_number_integer()) return std::nullopt;
      entry.expires = it->get<std::int64_t>();
    }
    if (!ReadBool(json, "s", &entry.secure) || !ReadBool(json, "h", &entry.http_only) ||
        !ReadString(json, "ss", &entry.same_site) || !ReadString(json, "vh", &entry.value_hash)) {
      return std::nullopt;
    }
  }
  if (entry.domain.empty() || entry.name.empty() || entry.path.empty()) return std::nullopt;
  return entry;
}

}  // namespace kelpie::sync
