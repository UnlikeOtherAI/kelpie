#include "sync_discovery_windows.h"

#include "sync_discovery_windows_state.h"

#include <algorithm>

#include "windows_utf.h"

namespace kelpie::windows {

using dnssd::Api;
using dnssd::Contexts;
using dnssd::Log;
using dnssd::ParseRecords;
using dnssd::Utf8;
using State = SyncDiscoveryWindows::State;
using Clock = State::Clock;
using dnssd::Ipv4Text;
using dnssd::Ipv6Text;

namespace {

void WINAPI OnBrowseComplete(DWORD status, PVOID context, PDNS_RECORD records) {
  auto parsed = ParseRecords(records);
  if (records != nullptr) Api().free_records(records, DnsFreeRecordList);
  const auto id = static_cast<std::uint64_t>(reinterpret_cast<std::uintptr_t>(context));
  // ERROR_CANCELLED is the last callback of a cancelled browse.
  if (status == ERROR_CANCELLED) {
    Contexts::Remove(id);
    return;
  }
  if (const auto state = Contexts::Find<State>(context)) state->OnBrowse(id, status, std::move(parsed));
}

void WINAPI OnResolveComplete(DWORD status, PVOID context, PDNS_SERVICE_INSTANCE instance) {
  const auto id = static_cast<std::uint64_t>(reinterpret_cast<std::uintptr_t>(context));
  const auto state = Contexts::Find<State>(context);
  Contexts::Remove(id);
  if (state) {
    std::string key;
    {
      std::lock_guard<std::mutex> lock(state->mutex);
      for (auto entry = state->resolves.begin(); entry != state->resolves.end(); ++entry) {
        if (entry->second.id == id) {
          key = entry->first;
          state->resolves.erase(entry);
          break;
        }
      }
    }
    if (!key.empty() && status == ERROR_SUCCESS) state->OnResolved(id, key, instance);
  }
  if (instance != nullptr) Api().free_instance(instance);
}

}  // namespace

bool SyncDiscoveryWindows::State::StartBrowse() {
  std::uint64_t id = 0;
  PVOID context = Contexts::Add(shared_from_this(), &id);
  DNS_SERVICE_BROWSE_REQUEST request{};
  request.Version = DNS_QUERY_REQUEST_VERSION1;
  request.InterfaceIndex = 0;
  request.QueryName = kBrowseName;
  request.pBrowseCallback = OnBrowseComplete;
  request.pQueryContext = context;
  DNS_SERVICE_CANCEL cancel{};
  {
    std::lock_guard<std::mutex> lock(mutex);
    if (browse_generation == 0) {
      Contexts::Remove(id);
      return false;
    }
    browse_id = id;
  }
  const DWORD status = Api().browse(&request, &cancel);
  std::lock_guard<std::mutex> lock(mutex);
  if (status != DNS_REQUEST_PENDING) {
    Log("browse rejected", status);
    Contexts::Remove(id);
    if (browse_id == id) browse_id = 0;
    return false;
  }
  if (browse_id == id) browse_cancel = cancel;
  return true;
}

void SyncDiscoveryWindows::State::CancelBrowse() {
  DNS_SERVICE_CANCEL cancel{};
  {
    std::lock_guard<std::mutex> lock(mutex);
    if (browse_id == 0) return;
    browse_id = 0;
    cancel = browse_cancel;
    browse_cancel = {};
  }
  // The final ERROR_CANCELLED callback releases the context.
  const DWORD status = Api().browse_cancel(&cancel);
  if (status != ERROR_SUCCESS) Log("browse cancel failed", status);
}

void SyncDiscoveryWindows::State::ScheduleRefresh() {
  std::uint64_t token = 0;
  {
    std::lock_guard<std::mutex> lock(mutex);
    token = ++refresh_token;
  }
  std::weak_ptr<State> weak = shared_from_this();
  PostAt(Clock::now() + kRefreshInterval, [weak, token] {
    const auto state = weak.lock();
    if (!state) return;
    {
      std::lock_guard<std::mutex> lock(state->mutex);
      if (token != state->refresh_token || state->browse_generation == 0) return;
    }
    state->CancelBrowse();
    DnsSdBrowseCache::Result expired;
    {
      std::lock_guard<std::mutex> lock(state->mutex);
      expired = state->cache.Expire(Clock::now());
    }
    state->Publish(expired);
    state->StartBrowse();
    state->ScheduleRefresh();
  });
}

void SyncDiscoveryWindows::State::OnBrowse(std::uint64_t id, DWORD status, std::vector<DnsSdRecord> records) {
  if (status != ERROR_SUCCESS) {
    Log("browse completed with error", status);
    return;
  }
  DnsSdBrowseCache::Result result;
  {
    std::lock_guard<std::mutex> lock(mutex);
    if (id != browse_id || browse_generation == 0) return;
    result = cache.Apply(records, Clock::now());
  }
  Publish(result);
}

void SyncDiscoveryWindows::State::OnResolved(std::uint64_t, const std::string& key, PDNS_SERVICE_INSTANCE instance) {
  if (instance == nullptr) return;
  std::vector<std::string> txt;
  for (DWORD index = 0; index < instance->dwPropertyCount; ++index) {
    txt.push_back(Utf8(instance->keys[index]) + "=" + Utf8(instance->values ? instance->values[index] : nullptr));
  }
  std::vector<std::string> addresses;
  if (instance->ip4Address != nullptr) addresses.push_back(Ipv4Text(*instance->ip4Address));
  if (instance->ip6Address != nullptr) addresses.push_back(Ipv6Text(*instance->ip6Address, instance->dwInterfaceIndex));
  DnsSdBrowseCache::Result result;
  {
    std::lock_guard<std::mutex> lock(mutex);
    if (browse_generation == 0) return;
    result = cache.Resolved(key, Utf8(instance->pszHostName), instance->wPort, txt, addresses, Clock::now());
    result.resolve.clear();  // one resolve per browse answer is enough
  }
  Publish(result);
}

void SyncDiscoveryWindows::State::Publish(const DnsSdBrowseCache::Result& result) {
  {
    // Delivered while holding the lock, so events reach the queue in the
    // order the table produced them even when DNS callbacks race.
    std::lock_guard<std::mutex> lock(mutex);
    if (browse_generation == 0) return;
    for (const auto& change : result.changes) {
      delivery.Deliver(browse_generation, change.view ? table.Update(change.instance, "", *change.view)
                                                      : table.Remove(change.instance, ""));
    }
  }
  for (const auto& key : result.resolve) StartResolve(key);
}

void SyncDiscoveryWindows::State::StartResolve(const std::string& key) {
  const auto name = utf::Utf8ToWide(key);
  if (!name) return;
  std::uint64_t id = 0;
  DNS_SERVICE_RESOLVE_REQUEST request{};
  DNS_SERVICE_CANCEL* cancel = nullptr;
  {
    std::lock_guard<std::mutex> lock(mutex);
    if (browse_generation == 0 || resolves.count(key) != 0) return;
    auto& resolve = resolves[key];
    request.pQueryContext = Contexts::Add(shared_from_this(), &resolve.id);
    resolve.name = *name;
    id = resolve.id;
    request.QueryName = resolve.name.data();
    cancel = &resolve.cancel;
  }
  request.Version = DNS_QUERY_REQUEST_VERSION1;
  request.InterfaceIndex = 0;
  request.pResolveCompletionCallback = OnResolveComplete;
  const DWORD status = Api().resolve(&request, cancel);
  if (status == DNS_REQUEST_PENDING) return;
  Log("resolve rejected", status);
  std::lock_guard<std::mutex> lock(mutex);
  const auto found = resolves.find(key);
  if (found != resolves.end() && found->second.id == id) resolves.erase(found);
  Contexts::Remove(id);
}

void SyncDiscoveryWindows::State::CancelResolves() {
  // Entries stay until their completion arrives, since Windows may still read
  // the query name; the completion erases them.
  std::vector<DNS_SERVICE_CANCEL> cancels;
  {
    std::lock_guard<std::mutex> lock(mutex);
    for (auto& [key, resolve] : resolves) cancels.push_back(resolve.cancel);
  }
  for (auto& cancel : cancels) Api().resolve_cancel(&cancel);
}

SyncDiscoveryWindows::SyncDiscoveryWindows() : state_(std::make_shared<State>()) {}

SyncDiscoveryWindows::~SyncDiscoveryWindows() {
  StopBrowsing();
  StopAdvertising();
  // Joins the worker here, never on a DNS thread that drops the last reference.
  state_->TakeQueue().reset();
}

bool SyncDiscoveryWindows::ApiAvailable() { return Api().available(); }

bool SyncDiscoveryWindows::Browse(std::function<void(const SyncPeerAdvert&)> found,
                                  std::function<void(const std::string& instance)> lost) {
  if (!ApiAvailable()) return false;
  StopBrowsing();
  const std::uint64_t generation = state_->delivery.Begin(std::move(found), std::move(lost));
  {
    std::lock_guard<std::mutex> lock(state_->mutex);
    state_->browse_generation = generation;
  }
  if (!state_->StartBrowse()) {
    StopBrowsing();
    return false;
  }
  state_->ScheduleRefresh();
  return true;
}

void SyncDiscoveryWindows::StopBrowsing() {
  state_->delivery.End();
  {
    std::lock_guard<std::mutex> lock(state_->mutex);
    state_->browse_generation = 0;
    ++state_->refresh_token;
    state_->cache.Clear();
    state_->table.Clear();
  }
  state_->CancelBrowse();
  state_->CancelResolves();
}

}  // namespace kelpie::windows
