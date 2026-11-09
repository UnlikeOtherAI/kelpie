#pragma once

#include <cstdint>
#include <optional>
#include <string>
#include <tuple>

#include <nlohmann/json.hpp>

#include "cookie.h"

namespace kelpie::sync {

// Hybrid logical clock stamp. Ordered by (wall, counter, replica).
struct Hlc {
  std::int64_t wall = 0;
  std::int64_t counter = 0;
  std::string replica;

  bool operator<(const Hlc& other) const {
    return std::tie(wall, counter, replica) < std::tie(other.wall, other.counter, other.replica);
  }
  bool operator==(const Hlc& other) const {
    return wall == other.wall && counter == other.counter && replica == other.replica;
  }
  bool operator>(const Hlc& other) const { return other < *this; }
};

// Accepts any non-negative JSON integer. nlohmann types a parsed positive
// number as unsigned but a C++-constructed one as signed; both are valid.
bool ReadUnsigned(const nlohmann::json& value, std::uint64_t* out);

nlohmann::json HlcToJson(const Hlc& hlc);
std::optional<Hlc> HlcFromJson(const nlohmann::json& json);

inline constexpr char kObservedAbsent[] = "absent";

// One cookie key's replication state. No cookie value is ever stored: the
// accepted record is its attributes plus the hash of its value, and `observed`
// is the fingerprint of what this device's engine actually holds.
struct Entry {
  std::string domain;
  std::string path;
  std::string name;
  Hlc hlc;
  bool deleted = false;

  // Accepted record (meaningless for tombstones).
  std::optional<std::int64_t> expires;
  bool secure = false;
  bool http_only = false;
  std::string same_site = "Unspecified";
  std::string value_hash;

  std::string observed = kObservedAbsent;
  bool unapplied = false;   // the engine refused or reshaped the accepted record
  bool local_only = false;  // belongs to a different account; never forwarded

  std::uint64_t seq = 0;  // change-feed position in this replica; not persisted

  std::string Key() const { return CookieKey(domain, path, name); }
  bool Live() const { return !deleted && !local_only; }
  // Unapplied sets are not forwarded because this device cannot supply the
  // value; the origin still has it. Unapplied tombstones are forwarded.
  bool Forwardable() const { return !local_only && (deleted || !unapplied); }
  // The cookie shape used for RFC 6265 coverage matching.
  Cookie Shape() const;
};

// Sets the accepted-record fields of `entry` from `cookie`.
void AcceptCookie(Entry* entry, const Cookie& cookie);

std::string ValueHash(const std::string& value);

nlohmann::json EntryToStoredJson(const Entry& entry);
std::optional<Entry> EntryFromStoredJson(const nlohmann::json& json);

}  // namespace kelpie::sync
