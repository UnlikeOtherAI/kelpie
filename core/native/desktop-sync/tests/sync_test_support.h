#pragma once

// Test doubles for the sync service: a fake UOA shared by several
// AccountServices, an in-memory default cookie store, and an in-process mDNS.

#include <atomic>
#include <chrono>
#include <filesystem>
#include <functional>
#include <map>
#include <mutex>
#include <random>
#include <set>
#include <string>
#include <thread>

#include <nlohmann/json.hpp>

#include "account_service.h"
#include "kelpie/desktop_sync.h"
#include "kelpie/sync_cookie_store.h"

namespace kelpie::sync_test {

using nlohmann::json;
using account::AccountFailure;
using account::AccountRequest;
using account::AccountResponse;

// Tickets are a deterministic function of subject, challenge and client id;
// validation checks all three and that the validator has the same subject.
struct FakeUoa {
  std::mutex mutex;
  std::map<std::string, std::string> subjects;  // bearer token → subject
  std::atomic<int> pairs{0}, validations{0};

  static std::string Ticket(const std::string& subject, const std::string& challenge, const std::string& client) {
    return "ticket|" + subject + "|" + challenge + "|" + client;
  }
  std::string SubjectOf(const std::string& token) {
    std::lock_guard lock(mutex);
    const auto it = subjects.find(token);
    if (it == subjects.end()) throw AccountFailure(401);
    return it->second;
  }
  AccountResponse Request(const std::string& path, const std::string& token, const std::string& body) {
    const std::string subject = SubjectOf(token);
    if (path == "/oauth/me") return {json{{"sub", subject}, {"email", subject + "@example.test"}}.dump(), {}};
    if (path == account::kAccountBookmarks) return {R"({"value":[]})", "v1"};
    if (path == "/oauth/me/avatar") throw AccountFailure(404);
    if (path == "/oauth/revoke") return {"{}", {}};
    const json request = json::parse(body);
    if (path == "/oauth/kelpie/pair") {
      ++pairs;
      return {json{{"pairing_ticket", Ticket(subject, request.at("challenge"), request.at("clientId"))},
                   {"expires_in", 120}}.dump(), {}};
    }
    if (path == "/oauth/kelpie/pair/validate") {
      ++validations;
      const bool active = request.at("ticket") == Ticket(subject, request.at("challenge"), request.at("clientId"));
      return {active ? R"({"active":true,"expires_at":1})" : R"({"active":false})", {}};
    }
    throw AccountFailure(404);
  }
  AccountRequest Transport() {
    return [this](const std::string& path, const std::string&, const std::string& token, const std::string& body,
                  const std::string&) { return Request(path, token, body); };
  }
};

inline std::string CookieId(const std::string& domain, const std::string& path, const std::string& name) {
  return json::array({domain, path, name}).dump();
}

inline std::string Bare(std::string domain) {
  if (!domain.empty() && domain.front() == '.') domain.erase(0, 1);
  return domain;
}

// The default store of one device, following the adapter read-back contract.
class FakeCookies final : public SyncCookieStore {
 public:
  bool Snapshot(json* cookies, json* coverage, const Cancelled&) override {
    std::lock_guard lock(mutex_);
    ++snapshots;
    *cookies = json::array();
    for (const auto& [key, cookie] : cookies_) cookies->push_back(cookie);
    *coverage = {{"all", true}};
    return true;
  }
  json Apply(const json& ops, const Cancelled&) override {
    std::lock_guard lock(mutex_);
    json results = json::array();
    for (const auto& op : ops) {
      const json& cookie = op["cookie"];
      const std::string key = CookieId(cookie["domain"], cookie.value("path", "/"), cookie["name"]);
      if (op["op"] == "delete") cookies_.erase(key); else cookies_[key] = cookie;
      json readback = json::array();
      for (const auto& [stored_key, stored] : cookies_) {
        if (stored["name"] == cookie["name"] && Bare(stored["domain"]) == Bare(cookie["domain"])) readback.push_back(stored);
      }
      results.push_back({{"id", op["id"]}, {"ok", true}, {"readback", readback}});
    }
    return results;
  }
  void SetChangeListener(std::function<void()> listener) override {
    std::lock_guard lock(listener_mutex_);
    listener_ = std::move(listener);
  }

  void Put(const std::string& domain, const std::string& name, const std::string& value,
           std::optional<std::int64_t> expires = 4102444800, const std::string& path = "/") {
    {
      std::lock_guard lock(mutex_);
      cookies_[CookieId(domain, path, name)] = {
          {"domain", domain}, {"path", path}, {"name", name}, {"value", value},
          {"expires", expires ? json(*expires) : json(nullptr)}, {"secure", true}, {"httpOnly", true},
          {"sameSite", "Lax"}};
    }
    Notify();
  }
  void Remove(const std::string& domain, const std::string& name, const std::string& path = "/") {
    {
      std::lock_guard lock(mutex_);
      cookies_.erase(CookieId(domain, path, name));
    }
    Notify();
  }
  void DropSessionCookies() {
    std::lock_guard lock(mutex_);
    for (auto it = cookies_.begin(); it != cookies_.end();) {
      it = it->second["expires"].is_null() ? cookies_.erase(it) : std::next(it);
    }
  }
  std::optional<std::string> Value(const std::string& domain, const std::string& name, const std::string& path = "/") {
    std::lock_guard lock(mutex_);
    const auto it = cookies_.find(CookieId(domain, path, name));
    if (it == cookies_.end()) return std::nullopt;
    return it->second["value"].get<std::string>();
  }
  json Get(const std::string& domain, const std::string& name, const std::string& path = "/") {
    std::lock_guard lock(mutex_);
    const auto it = cookies_.find(CookieId(domain, path, name));
    return it == cookies_.end() ? json() : it->second;
  }
  void Notify() {
    std::lock_guard lock(listener_mutex_);
    if (listener_) listener_();
  }
  std::atomic<int> snapshots{0};

 private:
  std::mutex mutex_;
  std::map<std::string, json> cookies_;
  std::mutex listener_mutex_;
  std::function<void()> listener_;
};

class FakeDiscovery;

// An in-process LAN: every advert reaches every other browser.
class FakeBus {
 public:
  void Advertise(FakeDiscovery* who, const SyncPeerAdvert& advert);
  void Withdraw(FakeDiscovery* who);
  void Browse(FakeDiscovery* who);
  void StopBrowsing(FakeDiscovery* who);

 private:
  std::mutex mutex_;
  std::map<FakeDiscovery*, SyncPeerAdvert> adverts_;
  std::set<FakeDiscovery*> browsers_;
};

class FakeDiscovery final : public SyncDiscovery {
 public:
  FakeDiscovery(FakeBus* bus, std::string instance) : bus_(bus), instance_(std::move(instance)) {}
  bool Advertise(int port, const std::map<std::string, std::string>& txt) override {
    port_ = port;
    bus_->Advertise(this, {instance_, {"127.0.0.1"}, port, txt});
    return true;
  }
  void UpdateTxt(const std::map<std::string, std::string>& txt) override {
    bus_->Advertise(this, {instance_, {"127.0.0.1"}, port_, txt});
  }
  void StopAdvertising() override { bus_->Withdraw(this); }
  bool Browse(std::function<void(const SyncPeerAdvert&)> found, std::function<void(const std::string&)> lost) override {
    found_ = std::move(found);
    lost_ = std::move(lost);
    bus_->Browse(this);
    return true;
  }
  void StopBrowsing() override { bus_->StopBrowsing(this); }
  int port() const { return port_; }

  std::function<void(const SyncPeerAdvert&)> found_;
  std::function<void(const std::string&)> lost_;

 private:
  FakeBus* bus_;
  std::string instance_;
  std::atomic<int> port_{0};
};

inline void FakeBus::Advertise(FakeDiscovery* who, const SyncPeerAdvert& advert) {
  std::lock_guard lock(mutex_);
  adverts_[who] = advert;
  for (auto* browser : browsers_) if (browser != who) browser->found_(advert);
}
inline void FakeBus::Withdraw(FakeDiscovery* who) {
  std::lock_guard lock(mutex_);
  const auto it = adverts_.find(who);
  if (it == adverts_.end()) return;
  const std::string instance = it->second.instance;
  adverts_.erase(it);
  for (auto* browser : browsers_) if (browser != who) browser->lost_(instance);
}
inline void FakeBus::Browse(FakeDiscovery* who) {
  std::lock_guard lock(mutex_);
  browsers_.insert(who);
  for (const auto& [owner, advert] : adverts_) if (owner != who) who->found_(advert);
}
inline void FakeBus::StopBrowsing(FakeDiscovery* who) {
  std::lock_guard lock(mutex_);
  browsers_.erase(who);
}

inline DesktopCookieSync::Timings FastTimings() {
  DesktopCookieSync::Timings t;
  t.warmup_window = std::chrono::milliseconds(300);
  t.warmup_limit = std::chrono::milliseconds(1500);
  t.initiator_fallback = std::chrono::milliseconds(400);
  t.session_lifetime = std::chrono::milliseconds(30000);
  t.scan_quiet = std::chrono::milliseconds(30);
  t.pull_wait = std::chrono::milliseconds(1500);
  t.backoff_min = std::chrono::milliseconds(100);
  t.backoff_max = std::chrono::milliseconds(1000);
  return t;
}

inline std::string Utf8(const std::filesystem::path& path) {
  const auto text = path.u8string();
  return std::string(text.begin(), text.end());
}

inline std::filesystem::path TempProfile(const std::string& name) {
  static std::mt19937_64 random(std::random_device{}());
  const auto dir = std::filesystem::temp_directory_path() / ("kelpie-desktop-sync-" + name + "-" + std::to_string(random()));
  std::filesystem::create_directories(dir);
  return dir;
}

template <typename Predicate>
bool WaitFor(Predicate&& predicate, std::chrono::milliseconds limit = std::chrono::milliseconds(20000)) {
  const auto until = std::chrono::steady_clock::now() + limit;
  while (std::chrono::steady_clock::now() < until) {
    if (predicate()) return true;
    std::this_thread::sleep_for(std::chrono::milliseconds(20));
  }
  return predicate();
}

}  // namespace kelpie::sync_test
