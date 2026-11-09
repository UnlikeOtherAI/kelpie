#include "avahi_sync_discovery.h"

#include <sys/time.h>

#include <mutex>
#include <tuple>

#include "avahi_api.h"
#include "sync_peer_events.h"

namespace kelpie::linuxapp {
namespace {

using avahi::AddressText;
using avahi::Api;
using avahi::Connected;
using avahi::Log;
using avahi::Source;
using avahi::TxtEntries;
using avahi::TxtList;

constexpr int kRetryMilliseconds = 5000;

}  // namespace

struct AvahiSyncDiscovery::State {
  using Key = std::tuple<AvahiIfIndex, AvahiProtocol, std::string>;

  // The worker that delivers found/lost; the owner joins it before the rest
  // of the state goes.
  std::mutex queue_mutex;
  std::unique_ptr<SyncSerialQueue> queue = std::make_unique<SyncSerialQueue>();
  SyncPeerDelivery delivery{[this](std::function<void()> task) {
    std::lock_guard<std::mutex> lock(queue_mutex);
    if (queue) queue->Post(std::move(task));
  }};

  // Serialises public calls. Everything below is touched only under the Avahi
  // poll lock, either by a public call or by an Avahi callback.
  std::mutex calls;
  AvahiThreadedPoll* poll = nullptr;
  AvahiClient* client = nullptr;
  AvahiTimeout* retry = nullptr;

  bool advertising = false;
  int port = 0;
  SyncTxt txt;
  std::string base_name;  // kelpie-<replicaId>
  std::string name;       // base_name, or Avahi's alternative after a collision
  AvahiEntryGroup* group = nullptr;

  bool browsing = false;
  std::uint64_t generation = 0;
  AvahiServiceBrowser* browser = nullptr;
  // Present instances; a null resolver is waiting for a retry.
  std::map<Key, AvahiServiceResolver*> resolvers;
  SyncPeerTable table;

  // Lifecycle (public-call side, `calls` held).
  bool Connect();
  void DisconnectIfIdle();
  void Lock() { Api().poll_lock(poll); }
  void Unlock() { Api().poll_unlock(poll); }

  // Under the poll lock.
  void Publish();
  void Withdraw();
  void StartBrowser();
  void StopBrowser(bool report);
  void Resolve(const Key& key);
  void ScheduleRetry();
  void Deliver(std::optional<SyncPeerTable::Event> event) { delivery.Deliver(generation, std::move(event)); }

  static void OnClient(AvahiClient* client, AvahiClientState state, void* context);
  static void OnGroup(AvahiEntryGroup* group, AvahiEntryGroupState state, void* context);
  static void OnBrowse(AvahiServiceBrowser* browser, AvahiIfIndex interface, AvahiProtocol protocol,
                       AvahiBrowserEvent event, const char* name, const char* type, const char* domain,
                       AvahiLookupResultFlags flags, void* context);
  static void OnResolve(AvahiServiceResolver* resolver, AvahiIfIndex interface, AvahiProtocol protocol,
                        AvahiResolverEvent event, const char* name, const char* type, const char* domain,
                        const char* host, const AvahiAddress* address, uint16_t port, AvahiStringList* txt,
                        AvahiLookupResultFlags flags, void* context);
  static void OnRetry(AvahiTimeout* timeout, void* context);
};

bool AvahiSyncDiscovery::State::Connect() {
  if (!Api().available) return false;
  if (poll != nullptr) {
    Lock();
    const bool connected = client != nullptr && Connected(Api().client_get_state(client));
    Unlock();
    if (connected) return true;
    DisconnectIfIdle();
    if (poll != nullptr) return false;
  }
  poll = Api().poll_new();
  if (poll == nullptr) return false;
  int error = 0;
  // The first connection has to succeed, or sync reports mdns-unavailable.
  // NO_FAIL matters for reconnects (see OnRetry): it waits for a restarting
  // daemon instead of failing.
  client = Api().client_new(Api().poll_get(poll), AVAHI_CLIENT_NO_FAIL, OnClient, this, &error);
  if (client == nullptr || !Connected(Api().client_get_state(client))) {
    Log("avahi daemon unavailable", client == nullptr ? error : AVAHI_ERR_NO_DAEMON);
    if (client != nullptr) Api().client_free(client);
    client = nullptr;
    Api().poll_free(poll);
    poll = nullptr;
    return false;
  }
  if (Api().poll_start(poll) < 0) {
    Api().client_free(client);
    client = nullptr;
    Api().poll_free(poll);
    poll = nullptr;
    return false;
  }
  return true;
}

void AvahiSyncDiscovery::State::DisconnectIfIdle() {
  if (poll == nullptr || advertising || browsing) return;
  // Stopping joins Avahi's thread, so nothing below races a callback.
  Api().poll_stop(poll);
  if (retry != nullptr) Api().poll_get(poll)->timeout_free(retry);
  retry = nullptr;
  for (auto& [key, resolver] : resolvers) {
    if (resolver != nullptr) Api().resolver_free(resolver);
  }
  resolvers.clear();
  if (browser != nullptr) Api().browser_free(browser);
  browser = nullptr;
  if (group != nullptr) Api().group_free(group);
  group = nullptr;
  if (client != nullptr) Api().client_free(client);
  client = nullptr;
  Api().poll_free(poll);
  poll = nullptr;
}

void AvahiSyncDiscovery::State::Publish() {
  if (!advertising || client == nullptr || Api().client_get_state(client) != AVAHI_CLIENT_S_RUNNING) return;
  if (group == nullptr) group = Api().group_new(client, OnGroup, this);
  if (group == nullptr) {
    Log("entry group failed", Api().client_errno(client));
    ScheduleRetry();
    return;
  }
  if (!Api().group_is_empty(group)) return;
  for (int attempt = 0; attempt < 8; ++attempt) {
    AvahiStringList* list = TxtList(txt);
    const int result = Api().group_add_service(group, AVAHI_IF_UNSPEC, AVAHI_PROTO_UNSPEC,
                                               static_cast<AvahiPublishFlags>(0), name.c_str(),
                                               kSyncServiceType, nullptr, nullptr,
                                               static_cast<uint16_t>(port), list);
    Api().string_list_free(list);
    if (result == AVAHI_ERR_COLLISION) {
      char* alternative = Api().alternative_service_name(name.c_str());
      name = alternative;
      Api().free(alternative);
      continue;
    }
    if (result < 0) {
      Log("add service failed", result);
      Api().group_reset(group);
      ScheduleRetry();
      return;
    }
    const int committed = Api().group_commit(group);
    if (committed < 0) {
      Log("commit failed", committed);
      ScheduleRetry();
    }
    return;
  }
}

void AvahiSyncDiscovery::State::Withdraw() {
  // Freeing the group withdraws its records with a goodbye.
  if (group != nullptr) Api().group_free(group);
  group = nullptr;
}

void AvahiSyncDiscovery::State::StartBrowser() {
  if (!browsing || browser != nullptr || client == nullptr || !Connected(Api().client_get_state(client))) return;
  browser = Api().browser_new(client, AVAHI_IF_UNSPEC, AVAHI_PROTO_UNSPEC, kSyncServiceType, nullptr,
                              static_cast<AvahiLookupFlags>(0), OnBrowse, this);
  if (browser == nullptr) {
    Log("browser failed", Api().client_errno(client));
    ScheduleRetry();
  }
}

void AvahiSyncDiscovery::State::StopBrowser(bool report) {
  for (auto& [key, resolver] : resolvers) {
    if (resolver != nullptr) Api().resolver_free(resolver);
  }
  resolvers.clear();
  if (browser != nullptr) Api().browser_free(browser);
  browser = nullptr;
  for (auto& event : table.Clear()) {
    if (report) Deliver(std::move(event));
  }
}

void AvahiSyncDiscovery::State::Resolve(const Key& key) {
  auto& resolver = resolvers[key];
  if (resolver != nullptr || client == nullptr) return;
  const auto& [interface, protocol, name] = key;
  // The resolver stays open, so later TXT changes (the daily hint) arrive too.
  resolver = Api().resolver_new(client, interface, protocol, name.c_str(), kSyncServiceType, "local", protocol,
                                static_cast<AvahiLookupFlags>(0), OnResolve, this);
  if (resolver == nullptr) {
    Log("resolver failed", Api().client_errno(client));
    ScheduleRetry();
  }
}

void AvahiSyncDiscovery::State::ScheduleRetry() {
  if (retry != nullptr || poll == nullptr) return;
  timeval when{};
  gettimeofday(&when, nullptr);
  when.tv_sec += kRetryMilliseconds / 1000;
  retry = Api().poll_get(poll)->timeout_new(Api().poll_get(poll), &when, OnRetry, this);
}

void AvahiSyncDiscovery::State::OnRetry(AvahiTimeout*, void* context) {
  auto* state = static_cast<State*>(context);
  Api().poll_get(state->poll)->timeout_free(state->retry);
  state->retry = nullptr;
  if (state->client == nullptr) {
    if (!state->advertising && !state->browsing) return;
    // Reconnect after the daemon went away; RUNNING restores everything.
    int error = 0;
    state->client = Api().client_new(Api().poll_get(state->poll), AVAHI_CLIENT_NO_FAIL, OnClient, state, &error);
    if (state->client == nullptr) {
      Log("avahi reconnect failed", error);
      state->ScheduleRetry();
    }
    return;
  }
  if (!Connected(Api().client_get_state(state->client))) return;
  if (state->group == nullptr || Api().group_is_empty(state->group)) state->Publish();
  state->StartBrowser();
  for (auto& [key, resolver] : state->resolvers) {
    if (resolver == nullptr) state->Resolve(key);
  }
}

void AvahiSyncDiscovery::State::OnClient(AvahiClient* client, AvahiClientState client_state, void* context) {
  auto* state = static_cast<State*>(context);
  // The first callback can arrive inside avahi_client_new, before it returns.
  if (state->client == nullptr) state->client = client;
  switch (client_state) {
    case AVAHI_CLIENT_S_RUNNING:
      state->Publish();
      state->StartBrowser();
      break;
    case AVAHI_CLIENT_S_COLLISION:
    case AVAHI_CLIENT_S_REGISTERING:
      // The host name is being (re)registered; services follow once running.
      if (state->group != nullptr) Api().group_reset(state->group);
      break;
    case AVAHI_CLIENT_CONNECTING:
      // Waiting for the daemon after a reconnect; nothing exists yet.
      break;
    case AVAHI_CLIENT_FAILURE:
      // Usually AVAHI_ERR_DISCONNECTED: the daemon restarted or stopped. The
      // client is unusable, every peer is gone, and a new client is made
      // later, as avahi-browse does. Our objects go before the client.
      Log("client failed", Api().client_errno(client));
      state->Withdraw();
      state->StopBrowser(true);
      if (client == state->client) state->client = nullptr;
      Api().client_free(client);
      state->ScheduleRetry();
      break;
  }
}

void AvahiSyncDiscovery::State::OnGroup(AvahiEntryGroup* group, AvahiEntryGroupState group_state, void* context) {
  auto* state = static_cast<State*>(context);
  if (group != state->group) return;
  if (group_state == AVAHI_ENTRY_GROUP_COLLISION) {
    char* alternative = Api().alternative_service_name(state->name.c_str());
    state->name = alternative;
    Api().free(alternative);
    Api().group_reset(group);
    state->Publish();
  } else if (group_state == AVAHI_ENTRY_GROUP_FAILURE) {
    Log("entry group failed", Api().client_errno(state->client));
    Api().group_reset(group);
    state->ScheduleRetry();
  }
}

void AvahiSyncDiscovery::State::OnBrowse(AvahiServiceBrowser* browser, AvahiIfIndex interface, AvahiProtocol protocol,
                                         AvahiBrowserEvent event, const char* name, const char*, const char*,
                                         AvahiLookupResultFlags flags, void* context) {
  auto* state = static_cast<State*>(context);
  if (browser != state->browser || name == nullptr) return;
  const Key key{interface, protocol, name};
  switch (event) {
    case AVAHI_BROWSER_NEW:
      if ((flags & AVAHI_LOOKUP_RESULT_OUR_OWN) != 0) return;
      state->Resolve(key);
      break;
    case AVAHI_BROWSER_REMOVE: {
      const auto found = state->resolvers.find(key);
      if (found != state->resolvers.end()) {
        if (found->second != nullptr) Api().resolver_free(found->second);
        state->resolvers.erase(found);
      }
      state->Deliver(state->table.Remove(name, Source(interface, protocol)));
      break;
    }
    case AVAHI_BROWSER_FAILURE:
      Log("browse failed", Api().client_errno(state->client));
      state->StopBrowser(true);
      state->ScheduleRetry();
      break;
    case AVAHI_BROWSER_ALL_FOR_NOW:
    case AVAHI_BROWSER_CACHE_EXHAUSTED:
      break;
  }
}

void AvahiSyncDiscovery::State::OnResolve(AvahiServiceResolver* resolver, AvahiIfIndex interface,
                                          AvahiProtocol protocol, AvahiResolverEvent event, const char* name,
                                          const char*, const char*, const char*, const AvahiAddress* address,
                                          uint16_t port, AvahiStringList* txt, AvahiLookupResultFlags flags,
                                          void* context) {
  auto* state = static_cast<State*>(context);
  if (name == nullptr) return;
  const Key key{interface, protocol, name};
  const auto found = state->resolvers.find(key);
  if (found == state->resolvers.end() || found->second != resolver) return;
  if (event == AVAHI_RESOLVER_FAILURE) {
    // Usually a timeout. The browser will not announce it again, so retry.
    Api().resolver_free(resolver);
    found->second = nullptr;
    state->Deliver(state->table.Remove(name, Source(interface, protocol)));
    state->ScheduleRetry();
    return;
  }
  if ((flags & AVAHI_LOOKUP_RESULT_OUR_OWN) != 0) return;
  SyncPeerView view;
  const std::string text = AddressText(address, interface);
  if (!text.empty()) view.addresses.push_back(text);
  view.port = port;
  view.txt = DecodeSyncTxt(TxtEntries(txt));
  state->Deliver(state->table.Update(name, Source(interface, protocol), std::move(view)));
}

AvahiSyncDiscovery::AvahiSyncDiscovery() : state_(std::make_unique<State>()) {}

AvahiSyncDiscovery::~AvahiSyncDiscovery() {
  StopBrowsing();
  StopAdvertising();
  std::unique_ptr<SyncSerialQueue> queue;
  {
    std::lock_guard<std::mutex> lock(state_->queue_mutex);
    queue = std::move(state_->queue);
  }
  queue.reset();
}

bool AvahiSyncDiscovery::LibraryAvailable() { return Api().available; }

bool AvahiSyncDiscovery::Advertise(int port, const std::map<std::string, std::string>& txt) {
  const std::string name = SyncInstanceName(txt);
  if (port <= 0 || port > 65535 || name.empty()) return false;
  std::lock_guard<std::mutex> calls(state_->calls);
  if (!state_->Connect()) return false;
  state_->Lock();
  state_->Withdraw();
  state_->advertising = true;
  state_->port = port;
  state_->txt = txt;
  state_->base_name = name;
  state_->name = name;
  state_->Publish();
  state_->Unlock();
  return true;
}

void AvahiSyncDiscovery::UpdateTxt(const std::map<std::string, std::string>& txt) {
  const std::string name = SyncInstanceName(txt);
  std::lock_guard<std::mutex> calls(state_->calls);
  if (state_->poll == nullptr || name.empty()) return;
  state_->Lock();
  if (state_->advertising && state_->txt != txt) {
    state_->txt = txt;
    if (name != state_->base_name) {
      // A new replica is a new instance: withdraw the old name first.
      state_->base_name = name;
      state_->name = name;
      state_->Withdraw();
      state_->Publish();
    } else if (state_->group != nullptr && !Api().group_is_empty(state_->group)) {
      AvahiStringList* list = TxtList(txt);
      const int result = Api().group_update_txt(state_->group, AVAHI_IF_UNSPEC, AVAHI_PROTO_UNSPEC,
                                                static_cast<AvahiPublishFlags>(0), state_->name.c_str(),
                                                kSyncServiceType, nullptr, list);
      Api().string_list_free(list);
      if (result < 0) Log("txt update failed", result);
    } else {
      state_->Publish();
    }
  }
  state_->Unlock();
}

void AvahiSyncDiscovery::StopAdvertising() {
  std::lock_guard<std::mutex> calls(state_->calls);
  if (state_->poll == nullptr) return;
  state_->Lock();
  state_->advertising = false;
  state_->Withdraw();
  state_->Unlock();
  state_->DisconnectIfIdle();
}

bool AvahiSyncDiscovery::Browse(std::function<void(const SyncPeerAdvert&)> found,
                                std::function<void(const std::string& instance)> lost) {
  std::lock_guard<std::mutex> calls(state_->calls);
  if (!state_->Connect()) return false;
  const std::uint64_t generation = state_->delivery.Begin(std::move(found), std::move(lost));
  state_->Lock();
  state_->StopBrowser(false);
  state_->browsing = true;
  state_->generation = generation;
  state_->StartBrowser();
  state_->Unlock();
  return true;
}

void AvahiSyncDiscovery::StopBrowsing() {
  state_->delivery.End();
  std::lock_guard<std::mutex> calls(state_->calls);
  if (state_->poll == nullptr) return;
  state_->Lock();
  state_->browsing = false;
  state_->StopBrowser(false);
  state_->Unlock();
  state_->DisconnectIfIdle();
}

}  // namespace kelpie::linuxapp
