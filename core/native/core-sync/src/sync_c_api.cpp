#include "kelpie/sync_c_api.h"

#include <cstdlib>
#include <cstring>
#include <memory>
#include <string>

#include <nlohmann/json.hpp>

#include "cookie.h"
#include "protocol.h"
#include "sync_store.h"

struct KelpieSyncStore {
  std::unique_ptr<kelpie::sync::SyncStore> store;
};

namespace {

using kelpie::sync::SyncError;
using nlohmann::json;

char* Duplicate(const std::string& text) {
  auto* out = static_cast<char*>(std::malloc(text.size() + 1));
  if (out == nullptr) return nullptr;
  std::memcpy(out, text.c_str(), text.size() + 1);
  return out;
}

char* ErrorJson(const std::string& code, const std::string& message) {
  return Duplicate(json{{"error", code}, {"message", message}}.dump());
}

json Parse(const char* text, const char* what) {
  if (text == nullptr) throw SyncError{"INVALID_JSON", std::string(what) + " is null"};
  auto parsed = json::parse(text, nullptr, false);
  if (parsed.is_discarded()) throw SyncError{"INVALID_JSON", std::string(what) + " is not JSON"};
  return parsed;
}

// Runs `body`, turning every failure into the documented error object so no
// C++ exception crosses the C boundary.
template <typename Body>
char* Guard(Body&& body) {
  try {
    return Duplicate(body().dump());
  } catch (const SyncError& error) {
    return ErrorJson(error.code, error.message);
  } catch (const json::exception&) {
    return ErrorJson("INVALID_JSON", "unexpected JSON shape");
  } catch (const std::exception& error) {
    return ErrorJson("INTERNAL", error.what());
  } catch (...) {
    return ErrorJson("INTERNAL", "unknown failure");
  }
}

kelpie::sync::SyncStore& Require(KelpieSyncStoreRef store) {
  if (store == nullptr || !store->store) throw SyncError{"NO_STORE", "store is closed"};
  return *store->store;
}

}  // namespace

extern "C" {

void kelpie_sync_free_string(char* str) { std::free(str); }

KelpieSyncStoreRef kelpie_sync_store_open(const char* path, const char* options_json, char** error_out) {
  if (error_out != nullptr) *error_out = nullptr;
  try {
    if (path == nullptr) throw SyncError{"INVALID_OPTIONS", "path is null"};
    const json options = Parse(options_json, "options");
    kelpie::sync::SyncStore::Options parsed;
    parsed.subject = options.value("subject", std::string());
    parsed.replica = options.value("replica", std::string());
    parsed.launch = options.value("launch", false);
    parsed.now_millis = options.value("nowMillis", static_cast<std::int64_t>(0));
    auto* handle = new KelpieSyncStore{kelpie::sync::SyncStore::Open(path, parsed)};
    return handle;
  } catch (const SyncError& error) {
    if (error_out != nullptr) *error_out = ErrorJson(error.code, error.message);
  } catch (const std::exception& error) {
    if (error_out != nullptr) *error_out = ErrorJson("INTERNAL", error.what());
  }
  return nullptr;
}

void kelpie_sync_store_close(KelpieSyncStoreRef store) { delete store; }

char* kelpie_sync_store_status(KelpieSyncStoreRef store) {
  return Guard([&] { return Require(store).Status(); });
}

void kelpie_sync_store_finish_warmup(KelpieSyncStoreRef store) {
  if (store != nullptr && store->store) store->store->FinishWarmup();
}

char* kelpie_sync_store_scan(KelpieSyncStoreRef store, const char* cookies_json, const char* coverage_json,
                             int64_t now_millis) {
  return Guard([&] {
    return Require(store).Scan(Parse(cookies_json, "cookies"), Parse(coverage_json, "coverage"), now_millis);
  });
}

char* kelpie_sync_store_rebase(KelpieSyncStoreRef store, const char* cookies_json, const char* coverage_json,
                               int64_t now_millis) {
  return Guard([&] {
    return Require(store).Rebase(Parse(cookies_json, "cookies"), Parse(coverage_json, "coverage"), now_millis);
  });
}

char* kelpie_sync_store_answer_pull(KelpieSyncStoreRef store, const char* pull_json, const char* cookies_json,
                                    const char* coverage_json, int64_t now_millis) {
  return Guard([&] {
    return Require(store).AnswerPull(Parse(pull_json, "pull"), Parse(cookies_json, "cookies"),
                                     Parse(coverage_json, "coverage"), now_millis);
  });
}

char* kelpie_sync_store_build_push(KelpieSyncStoreRef store, const char* watermark_json, const char* cookies_json,
                                   const char* coverage_json, int64_t now_millis) {
  return Guard([&] {
    return Require(store).BuildPush(Parse(watermark_json, "watermark"), Parse(cookies_json, "cookies"),
                                    Parse(coverage_json, "coverage"), now_millis);
  });
}

char* kelpie_sync_store_plan_merge(KelpieSyncStoreRef store, const char* records_json, const char* source_json,
                                   int64_t now_millis) {
  return Guard([&] {
    const json source = source_json == nullptr ? json(nullptr) : Parse(source_json, "source");
    return Require(store).PlanMerge(Parse(records_json, "records"), source, now_millis);
  });
}

char* kelpie_sync_store_commit_merge(KelpieSyncStoreRef store, const char* results_json) {
  return Guard([&] { return Require(store).CommitMerge(Parse(results_json, "results")); });
}

void kelpie_sync_store_abort_merge(KelpieSyncStoreRef store) {
  if (store != nullptr && store->store) store->store->AbortMerge();
}

char* kelpie_sync_store_watermark(KelpieSyncStoreRef store, const char* replica) {
  return Guard([&] { return Require(store).Watermark(replica == nullptr ? "" : replica); });
}

char* kelpie_sync_validate(const char* kind, const char* message_json) {
  return Guard([&] {
    const std::string reason = kelpie::sync::ValidateMessage(kind == nullptr ? "" : kind,
                                                             Parse(message_json, "message"));
    return reason.empty() ? json{{"ok", true}} : json{{"ok", false}, {"error", reason}};
  });
}

char* kelpie_sync_transcript(const char* hello_pair_json) {
  return Guard([&] {
    try {
      return json{{"challenge", kelpie::sync::TranscriptChallenge(Parse(hello_pair_json, "hello pair"))}};
    } catch (const std::invalid_argument&) {
      throw SyncError{"INVALID_MESSAGE", "transcript needs replica, key and nonce for initiator and responder"};
    }
  });
}

char* kelpie_sync_account_hints(const char* subject, int64_t now_millis) {
  return Guard([&] {
    const std::string value = subject == nullptr ? "" : subject;
    if (value.empty()) throw SyncError{"INVALID_OPTIONS", "subject is required"};
    return json{{"current", kelpie::sync::AccountHint(value, now_millis)},
                {"accepted", kelpie::sync::AcceptedAccountHints(value, now_millis)}};
  });
}

char* kelpie_sync_canonical_cookie(const char* cookie_json) {
  return Guard([&] {
    const auto parsed = kelpie::sync::ParseCookie(Parse(cookie_json, "cookie"));
    if (!parsed.cookie) {
      return json{{"syncable", false}, {"reason", kelpie::sync::CookieProblemName(parsed.problem)}};
    }
    return json{{"syncable", true},
                {"key", kelpie::sync::CookieKey(*parsed.cookie)},
                {"cookie", kelpie::sync::CookieToJson(*parsed.cookie)}};
  });
}

}  // extern "C"
