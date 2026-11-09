#include <algorithm>
#include <cassert>
#include <filesystem>
#include <fstream>
#include <random>
#include <cstdlib>
#include <cstring>
#include <string>

#include <nlohmann/json.hpp>

#include "base64url.h"
#include "kelpie/sync_c_api.h"
#include "protocol.h"

using namespace kelpie::sync;
using nlohmann::json;

namespace {

std::string Bytes(std::size_t count, unsigned char fill) {
  return Base64UrlEncode(std::string(count, static_cast<char>(fill)));
}

std::string Point() {
  std::string raw(65, '\x11');
  raw[0] = '\x04';
  return Base64UrlEncode(raw);
}

json Hello() {
  return {{"v", 1},           {"replica", Bytes(16, 1)}, {"hint", Bytes(8, 2)}, {"now", 1767225600000},
          {"platform", "macos"}, {"name", "Studio Mac"},  {"key", Point()},      {"nonce", Bytes(32, 3)}};
}

void TestValidation() {
  assert(ValidateMessage("hello", Hello()).empty());

  json wrong_version = Hello();
  wrong_version["v"] = 2;
  assert(!ValidateMessage("hello", wrong_version).empty());

  json compressed_key = Hello();
  std::string raw(33, '\x11');
  raw[0] = '\x02';
  compressed_key["key"] = Base64UrlEncode(raw);
  assert(!ValidateMessage("hello", compressed_key).empty());

  json control_name = Hello();
  control_name["name"] = std::string("bad\nname");
  assert(!ValidateMessage("hello", control_name).empty());

  json long_name = Hello();
  long_name["name"] = std::string(65, 'x');
  assert(!ValidateMessage("hello", long_name).empty());

  json platform = Hello();
  platform["platform"] = "Mac OS";
  assert(!ValidateMessage("hello", platform).empty());

  json reply = Hello();
  reply.erase("hint");
  reply["handshakeId"] = Bytes(32, 4);
  reply["expiresAt"] = 1767225660000;
  assert(ValidateMessage("hello-reply", reply).empty());

  assert(ValidateMessage("auth", {{"handshakeId", Bytes(32, 4)}, {"ticket", "eyJ.abc.def"}}).empty());
  assert(!ValidateMessage("auth", {{"handshakeId", Bytes(31, 4)}, {"ticket", "t"}}).empty());
  assert(!ValidateMessage("auth", {{"handshakeId", Bytes(32, 4)}, {"ticket", std::string(8193, 'a')}}).empty());
  assert(ValidateMessage("auth-reply", {{"ticket", "t"}, {"sessionExpiresAt", 1}}).empty());

  assert(ValidateMessage("exchange", {{"seq", 1}, {"box", Bytes(16, 5)}}).empty());
  assert(!ValidateMessage("exchange", {{"seq", 0}, {"box", Bytes(16, 5)}}).empty());
  assert(!ValidateMessage("exchange", {{"seq", 1}, {"box", Bytes(15, 5)}}).empty());
  assert(!ValidateMessage("unknown", json::object()).empty());
}

void TestTranscript() {
  const json pair = {{"initiator", {{"replica", "ri"}, {"key", "ki"}, {"nonce", "ni"}}},
                     {"responder", {{"replica", "rr"}, {"key", "kr"}, {"nonce", "nr"}}}};
  const std::string challenge = TranscriptChallenge(pair);
  assert(challenge.size() == 43);
  assert(challenge == TranscriptChallenge(pair));

  json swapped = pair;
  std::swap(swapped["initiator"], swapped["responder"]);
  assert(TranscriptChallenge(swapped) != challenge);  // roles are bound

  json shifted = pair;
  shifted["initiator"]["replica"] = "r";
  shifted["initiator"]["key"] = "iki";  // same concatenation without separators
  assert(TranscriptChallenge(shifted) != challenge);
}

void TestSharedVectors() {
  // The same file Swift, Kotlin, CNG and OpenSSL tests check; see
  // packages/shared/tests/cookie-sync-vectors.test.ts for the Node proof.
  std::ifstream input(std::filesystem::u8path(KELPIE_SYNC_VECTORS));
  assert(input);
  const json vectors = json::parse(input);
  const json pair = {
      {"initiator", {{"replica", vectors["initiator"]["replica"]}, {"key", vectors["initiator"]["key"]},
                     {"nonce", vectors["initiator"]["nonce"]}}},
      {"responder", {{"replica", vectors["responder"]["replica"]}, {"key", vectors["responder"]["key"]},
                     {"nonce", vectors["responder"]["nonce"]}}},
  };
  assert(TranscriptChallenge(pair) == vectors["challenge"].get<std::string>());

  json hello = Hello();
  hello["replica"] = vectors["initiator"]["replica"];
  hello["key"] = vectors["initiator"]["key"];
  hello["nonce"] = vectors["initiator"]["nonce"];
  assert(ValidateMessage("hello", hello).empty());
  for (const auto& message : vectors["messages"]) {
    assert(ValidateMessage("exchange", {{"seq", message["seq"]}, {"box", message["box"]}}).empty());
  }
}

void TestHints() {
  assert(UtcDate(0) == "1970-01-01");
  assert(UtcDate(1767225600000) == "2026-01-01");
  assert(UtcDate(1767225599999) == "2025-12-31");
  assert(UtcDate(951782400000) == "2000-02-29");

  const std::string today = AccountHint("subject", 1767225600000);
  assert(today.size() == 11);
  assert(today == AccountHint("subject", 1767225600000 + 3600000));  // same UTC day
  assert(today != AccountHint("subject", 1767225600000 + 86400000));
  assert(today != AccountHint("other", 1767225600000));

  // Around midnight each side accepts the other's hint.
  const auto before_midnight = AcceptedAccountHints("subject", 1767225599000);
  const std::string after_midnight = AccountHint("subject", 1767225601000);
  assert(std::find(before_midnight.begin(), before_midnight.end(), after_midnight) != before_midnight.end());
}

std::string Take(char* text) {
  std::string out = text == nullptr ? "" : text;
  kelpie_sync_free_string(text);
  return out;
}

void TestCApi() {
  assert(json::parse(Take(kelpie_sync_validate("hello", Hello().dump().c_str())))["ok"] == true);
  assert(json::parse(Take(kelpie_sync_validate("hello", "{not json")))["error"] == "INVALID_JSON");
  assert(json::parse(Take(kelpie_sync_transcript("{}")))["error"] == "INVALID_MESSAGE");
  assert(json::parse(Take(kelpie_sync_account_hints("subject", 0)))["accepted"].size() == 3);

  const json canonical = json::parse(Take(kelpie_sync_canonical_cookie(
      R"({"domain":"Example.com","name":"a","value":"b","sameSite":"strict"})")));
  assert(canonical["syncable"] == true && canonical["cookie"]["sameSite"] == "Strict");
  assert(json::parse(Take(kelpie_sync_canonical_cookie(
             R"({"domain":"localhost","name":"a","value":"b","sameSite":"Lax"})")))["reason"] == "loopback_host");

  // A path whose parent is a regular file cannot be created on any platform.
  const auto blocker = std::filesystem::temp_directory_path() /
                       ("kelpie-sync-blocker-" + std::to_string(std::random_device{}()));
  { std::ofstream(blocker) << "file"; }
  const std::string unwritable = (blocker / "store.json").u8string();
  char* error = nullptr;
  assert(kelpie_sync_store_open(unwritable.c_str(), R"({"subject":"s","replica":"r"})", &error) == nullptr);
  assert(json::parse(Take(error))["error"] == "IO");
  std::filesystem::remove(blocker);
  assert(kelpie_sync_store_open(unwritable.c_str(), R"({"subject":"","replica":"r"})", &error) == nullptr);
  assert(json::parse(Take(error))["error"] == "INVALID_OPTIONS");
  assert(json::parse(Take(kelpie_sync_store_status(nullptr)))["error"] == "NO_STORE");
}

}  // namespace

int main() {
  TestValidation();
  TestTranscript();
  TestSharedVectors();
  TestHints();
  TestCApi();
  return 0;
}
