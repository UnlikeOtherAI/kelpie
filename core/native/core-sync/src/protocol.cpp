#include "protocol.h"

#include <cstdio>
#include <stdexcept>

#include "base64url.h"
#include "sha256.h"
#include "sync_entry.h"

namespace kelpie::sync {
namespace {

constexpr std::int64_t kMillisPerDay = 86400000;

bool Base64Field(const nlohmann::json& message, const char* field, std::size_t bytes) {
  const auto it = message.find(field);
  if (it == message.end() || !it->is_string()) return false;
  const auto decoded = Base64UrlDecode(it->get<std::string>());
  return decoded && decoded->size() == bytes;
}

bool IntegerField(const nlohmann::json& message, const char* field) {
  const auto it = message.find(field);
  return it != message.end() && it->is_number_integer();
}

bool PrintableField(const nlohmann::json& message, const char* field, std::size_t min, std::size_t max) {
  const auto it = message.find(field);
  if (it == message.end() || !it->is_string()) return false;
  const auto& text = it->get_ref<const std::string&>();
  if (text.size() < min || text.size() > max) return false;
  for (const unsigned char c : text) {
    if (c < 0x20 || c == 0x7f) return false;
  }
  return true;
}

bool PlatformField(const nlohmann::json& message) {
  const auto it = message.find("platform");
  if (it == message.end() || !it->is_string()) return false;
  const auto& text = it->get_ref<const std::string&>();
  if (text.empty() || text.size() > 32) return false;
  for (const char c : text) {
    if (!((c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') || c == '-')) return false;
  }
  return true;
}

// An uncompressed P-256 point: 0x04 || X || Y. The platform crypto library
// still checks that the point is on the curve.
bool PublicKeyField(const nlohmann::json& message) {
  const auto it = message.find("key");
  if (it == message.end() || !it->is_string()) return false;
  const auto decoded = Base64UrlDecode(it->get<std::string>());
  return decoded && decoded->size() == 65 && (*decoded)[0] == 0x04;
}

std::string ValidateHelloFields(const nlohmann::json& message) {
  if (message.value("v", 0) != kProtocolVersion) return "unsupported version";
  if (!Base64Field(message, "replica", 16)) return "invalid replica";
  if (!IntegerField(message, "now")) return "invalid now";
  if (!PlatformField(message)) return "invalid platform";
  if (!PrintableField(message, "name", 0, 64)) return "invalid name";
  if (!PublicKeyField(message)) return "invalid key";
  if (!Base64Field(message, "nonce", 32)) return "invalid nonce";
  return "";
}

std::string Part(const nlohmann::json& side, const char* field) {
  const auto it = side.find(field);
  if (it == side.end() || !it->is_string()) throw std::invalid_argument(field);
  return it->get<std::string>();
}

}  // namespace

std::string ValidateMessage(const std::string& kind, const nlohmann::json& message) {
  if (!message.is_object()) return "not an object";
  if (kind == "hello") {
    if (!Base64Field(message, "hint", 8)) return "invalid hint";
    return ValidateHelloFields(message);
  }
  if (kind == "hello-reply") {
    if (!Base64Field(message, "handshakeId", 32)) return "invalid handshakeId";
    if (!IntegerField(message, "expiresAt")) return "invalid expiresAt";
    return ValidateHelloFields(message);
  }
  if (kind == "auth") {
    if (!Base64Field(message, "handshakeId", 32)) return "invalid handshakeId";
    if (!PrintableField(message, "ticket", 1, 8192)) return "invalid ticket";
    return "";
  }
  if (kind == "auth-reply") {
    if (!PrintableField(message, "ticket", 1, 8192)) return "invalid ticket";
    if (!IntegerField(message, "sessionExpiresAt")) return "invalid sessionExpiresAt";
    return "";
  }
  if (kind == "exchange") {
    const auto seq = message.find("seq");
    std::uint64_t seq_value = 0;
    if (seq == message.end() || !ReadUnsigned(*seq, &seq_value) || seq_value == 0) return "invalid seq";
    const auto box = message.find("box");
    if (box == message.end() || !box->is_string()) return "invalid box";
    const auto decoded = Base64UrlDecode(box->get<std::string>());
    if (!decoded || decoded->size() < 16) return "invalid box";
    return "";
  }
  return "unknown kind";
}

std::string TranscriptChallenge(const nlohmann::json& hello_pair) {
  const auto initiator = hello_pair.at("initiator");
  const auto responder = hello_pair.at("responder");
  Sha256 hasher;
  const char zero = '\0';
  hasher.Update("kelpie-sync-v1");
  for (const auto* side : {&initiator, &responder}) {
    for (const char* field : {"replica", "key", "nonce"}) {
      hasher.Update(&zero, 1);
      hasher.Update(Part(*side, field));
    }
  }
  const auto digest = hasher.Finish();
  return Base64UrlEncode(digest.data(), digest.size());
}

std::string UtcDate(std::int64_t now_millis) {
  // Howard Hinnant's civil_from_days, valid for the whole int64 day range used here.
  std::int64_t days = now_millis >= 0 ? now_millis / kMillisPerDay : (now_millis - kMillisPerDay + 1) / kMillisPerDay;
  days += 719468;
  const std::int64_t era = (days >= 0 ? days : days - 146096) / 146097;
  const std::int64_t doe = days - era * 146097;
  const std::int64_t yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365;
  std::int64_t year = yoe + era * 400;
  const std::int64_t doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
  const std::int64_t mp = (5 * doy + 2) / 153;
  const std::int64_t day = doy - (153 * mp + 2) / 5 + 1;
  const std::int64_t month = mp < 10 ? mp + 3 : mp - 9;
  if (month <= 2) ++year;
  char buffer[16];
  std::snprintf(buffer, sizeof(buffer), "%04lld-%02lld-%02lld", static_cast<long long>(year),
                static_cast<long long>(month), static_cast<long long>(day));
  return buffer;
}

std::string AccountHint(const std::string& subject, std::int64_t now_millis) {
  Sha256 hasher;
  const char zero = '\0';
  hasher.Update("kelpie-sync-hint-v1");
  hasher.Update(&zero, 1);
  hasher.Update(subject);
  hasher.Update(&zero, 1);
  hasher.Update(UtcDate(now_millis));
  const auto digest = hasher.Finish();
  return Base64UrlEncode(digest.data(), 8);
}

std::vector<std::string> AcceptedAccountHints(const std::string& subject, std::int64_t now_millis) {
  return {AccountHint(subject, now_millis - kMillisPerDay), AccountHint(subject, now_millis),
          AccountHint(subject, now_millis + kMillisPerDay)};
}

}  // namespace kelpie::sync
