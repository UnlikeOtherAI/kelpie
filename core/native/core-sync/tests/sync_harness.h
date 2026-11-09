#pragma once

// Test-only fake engine and sync driver. The fake engine stands in for a
// browser cookie store and can mimic the quirks real engines have: dropping
// attributes, refusing writes and storing a cookie under a different key.

#include <cassert>
#include <cstdio>
#include <cstdint>
#include <filesystem>
#include <map>
#include <memory>
#include <random>
#include <string>

#include <nlohmann/json.hpp>

#include "cookie.h"
#include "sync_store.h"

namespace kelpie::sync::testing {

using nlohmann::json;

inline json MakeCookie(const std::string& domain, const std::string& name, const std::string& value,
                       std::optional<std::int64_t> expires = 4102444800, const std::string& path = "/") {
  return {{"domain", domain}, {"path", path},   {"name", name},          {"value", value},
          {"expires", expires ? json(*expires) : json(nullptr)},
          {"secure", true},     {"httpOnly", true}, {"sameSite", "Lax"}};
}

struct FakeEngine {
  std::map<std::string, json> cookies;  // key → wire cookie
  bool drops_same_site = false;         // reads back sameSite as "Unspecified"
  bool refuses_writes = false;          // set succeeds but nothing is stored
  bool host_only_only = false;          // stores ".example.com" as "example.com"

  static std::string KeyOf(const json& cookie) {
    const auto parsed = ParseCookie(cookie);
    assert(parsed.cookie);
    return CookieKey(*parsed.cookie);
  }

  void Put(const json& cookie) { cookies[KeyOf(cookie)] = cookie; }
  void Remove(const std::string& domain, const std::string& name, const std::string& path = "/") {
    cookies.erase(CookieKey(domain, path, name));
  }
  bool Has(const std::string& domain, const std::string& name, const std::string& path = "/") const {
    return cookies.count(CookieKey(domain, path, name)) != 0;
  }
  std::string ValueOf(const std::string& domain, const std::string& name, const std::string& path = "/") const {
    const auto it = cookies.find(CookieKey(domain, path, name));
    return it == cookies.end() ? std::string() : it->second["value"].get<std::string>();
  }

  json Snapshot() const {
    json out = json::array();
    for (const auto& [key, cookie] : cookies) out.push_back(cookie);
    return out;
  }

  // Applies planned ops the way a platform adapter must: write, then read
  // back every cookie with the same name for the domain.
  json Apply(const json& plan) {
    json results = json::array();
    for (const auto& op : plan["ops"]) {
      json cookie = op["cookie"];
      bool ok = true;
      if (op["op"] == "delete") {
        cookies.erase(KeyOf(json{{"domain", cookie["domain"]}, {"path", cookie["path"]}, {"name", cookie["name"]},
                                 {"value", ""}, {"sameSite", "Unspecified"}}));
      } else if (!refuses_writes) {
        if (drops_same_site) cookie["sameSite"] = "Unspecified";
        if (host_only_only) {
          std::string domain = cookie["domain"].get<std::string>();
          if (!domain.empty() && domain.front() == '.') cookie["domain"] = domain.substr(1);
        }
        Put(cookie);
      }
      results.push_back({{"id", op["id"]}, {"ok", ok}, {"readback", Readback(cookie)}});
    }
    return results;
  }

  json Readback(const json& cookie) const {
    std::string host = cookie["domain"].get<std::string>();
    if (!host.empty() && host.front() == '.') host = host.substr(1);
    json out = json::array();
    for (const auto& [key, stored] : cookies) {
      std::string stored_host = stored["domain"].get<std::string>();
      if (!stored_host.empty() && stored_host.front() == '.') stored_host = stored_host.substr(1);
      if (stored_host == host && stored["name"] == cookie["name"]) out.push_back(stored);
    }
    return out;
  }
};

inline std::string TempPath(const std::string& name) {
  static std::mt19937_64 random(std::random_device{}());
  const auto dir = std::filesystem::temp_directory_path() /
                   ("kelpie-sync-test-" + std::to_string(random()));
  std::filesystem::create_directories(dir);
  return (dir / name).u8string();
}

struct Device {
  std::string path;
  std::string subject;
  std::string replica;
  FakeEngine engine;
  std::unique_ptr<SyncStore> store;
  int launches = 0;

  Device(const std::string& id, const std::string& subject_id = "alice")
      : path(TempPath(id + ".json")), subject(subject_id) {}

  void Open(bool launch, std::int64_t now, const std::string& as_subject = "") {
    if (!as_subject.empty()) subject = as_subject;
    replica = "r" + std::to_string(++launches) + "-" + path.substr(path.size() - 12, 7);
    store = SyncStore::Open(path, SyncStore::Options{subject, replica, launch, now});
  }

  json Scan(std::int64_t now) { return store->Scan(engine.Snapshot(), json{{"all", true}}, now); }
};

// One full pull from `from` into `to`, page by page, like an initiator would.
inline void PullAll(Device& to, Device& from, std::int64_t now) {
  for (int guard = 0; guard < 100; ++guard) {
    const json since = to.store->Watermark(from.replica);
    const json pull = {{"op", "pull"}, {"replica", to.replica}, {"since", since}, {"wait", 0}};
    const json response = from.store->AnswerPull(pull, from.engine.Snapshot(), json{{"all", true}}, now);
    assert(!response.contains("error"));
    if (response["warming"] == true) return;
    const json plan = to.store->PlanMerge(response["records"],
                                          json{{"replica", response["replica"]}, {"seq", response["seq"]}}, now);
    to.store->CommitMerge(to.engine.Apply(plan));
    if (response["more"] != true) return;
  }
  assert(false && "pull did not finish");
}

// One full push from `from` to `to`, using `to`'s watermark of `from`.
inline void PushAll(Device& from, Device& to, std::int64_t now) {
  for (int guard = 0; guard < 100; ++guard) {
    const json watermark = to.store->Watermark(from.replica);
    const json built = from.store->BuildPush(watermark, from.engine.Snapshot(), json{{"all", true}}, now);
    if (built["push"].is_null()) return;
    const json& push = built["push"];
    const json plan =
        to.store->PlanMerge(push["records"], json{{"replica", push["replica"]}, {"seq", push["seq"]}}, now);
    to.store->CommitMerge(to.engine.Apply(plan));
    if (push["more"] != true) return;
  }
  assert(false && "push did not finish");
}

inline void Sync(Device& a, Device& b, std::int64_t now) {
  PullAll(a, b, now);
  PushAll(a, b, now);
}

// Reports an escaping exception instead of a bare abort, so CTest shows why.
template <typename Body>
int RunGuarded(Body&& body) {
  try {
    body();
    return 0;
  } catch (const SyncError& error) {
    std::fprintf(stderr, "SyncError %s: %s\n", error.code.c_str(), error.message.c_str());
  } catch (const std::exception& error) {
    std::fprintf(stderr, "exception: %s\n", error.what());
  }
  return 1;
}

}  // namespace kelpie::sync::testing
