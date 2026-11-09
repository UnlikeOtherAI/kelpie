#include "sync_discovery_windows.h"

#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <winsock2.h>
#include <ws2tcpip.h>
#include <windows.h>
#include <windns.h>

#include <algorithm>
#include <condition_variable>
#include <cstdio>
#include <map>
#include <mutex>
#include <optional>
#include <set>

#include "dnssd_browse_cache.h"
#include "sync_peer_events.h"
#include "windows_utf.h"

namespace kelpie::windows {
namespace {

using Clock = std::chrono::steady_clock;

constexpr wchar_t kBrowseName[] = L"_kelpie-sync._tcp.local";
constexpr char kServiceDomain[] = "_kelpie-sync._tcp.local";
// Windows does not re-deliver a browse on its own; restarting it refreshes
// TXT records (the account hint changes daily) and record TTLs.
constexpr auto kRefreshInterval = std::chrono::minutes(5);
constexpr auto kStopWait = std::chrono::seconds(3);
constexpr auto kRetryFirst = std::chrono::seconds(5);
constexpr auto kRetryMax = std::chrono::minutes(5);

// Codes only: names, TXT values and addresses never reach the log.
void Log(const char* event, unsigned long code) {
  char line[160];
  std::snprintf(line, sizeof(line), "kelpie sync discovery: %s (%lu)\n", event, code);
  OutputDebugStringA(line);
}

struct DnsApi {
  decltype(&DnsServiceConstructInstance) construct = nullptr;
  decltype(&DnsServiceFreeInstance) free_instance = nullptr;
  decltype(&DnsServiceRegister) register_service = nullptr;
  decltype(&DnsServiceDeRegister) deregister_service = nullptr;
  decltype(&DnsServiceBrowse) browse = nullptr;
  decltype(&DnsServiceBrowseCancel) browse_cancel = nullptr;
  decltype(&DnsServiceResolve) resolve = nullptr;
  decltype(&DnsServiceResolveCancel) resolve_cancel = nullptr;
  decltype(&DnsFree) free_records = nullptr;

  bool available() const {
    return construct && free_instance && register_service && deregister_service && browse &&
           browse_cancel && resolve && resolve_cancel && free_records;
  }
};

template <typename Function>
void Load(HMODULE module, const char* name, Function* target) {
  *target = reinterpret_cast<Function>(reinterpret_cast<void*>(GetProcAddress(module, name)));
}

// Looked up once; dnsapi.dll stays loaded for the life of the process.
const DnsApi& Api() {
  static const DnsApi api = [] {
    DnsApi loaded;
    HMODULE module = LoadLibraryExW(L"dnsapi.dll", nullptr, LOAD_LIBRARY_SEARCH_SYSTEM32);
    if (module == nullptr) return loaded;
    Load(module, "DnsServiceConstructInstance", &loaded.construct);
    Load(module, "DnsServiceFreeInstance", &loaded.free_instance);
    Load(module, "DnsServiceRegister", &loaded.register_service);
    Load(module, "DnsServiceDeRegister", &loaded.deregister_service);
    Load(module, "DnsServiceBrowse", &loaded.browse);
    Load(module, "DnsServiceBrowseCancel", &loaded.browse_cancel);
    Load(module, "DnsServiceResolve", &loaded.resolve);
    Load(module, "DnsServiceResolveCancel", &loaded.resolve_cancel);
    Load(module, "DnsFree", &loaded.free_records);
    return loaded;
  }();
  return api;
}

std::string Utf8(PCWSTR value) {
  if (value == nullptr) return {};
  return utf::WideToUtf8(value).value_or(std::string());
}

std::string Ipv4Text(const IP4_ADDRESS& address) {
  char text[INET_ADDRSTRLEN] = {};
  IN_ADDR raw{};
  raw.S_un.S_addr = address;
  return inet_ntop(AF_INET, &raw, text, sizeof(text)) != nullptr ? text : std::string();
}

// Link-local IPv6 needs a scope; without one the address is unusable.
std::string Ipv6Text(const IP6_ADDRESS& address, DWORD interface_index) {
  IN6_ADDR raw{};
  static_assert(sizeof(raw) == sizeof(address.IP6Byte));
  std::copy(std::begin(address.IP6Byte), std::end(address.IP6Byte), raw.u.Byte);
  const bool link_local = raw.u.Byte[0] == 0xFE && (raw.u.Byte[1] & 0xC0) == 0x80;
  if (link_local && interface_index == 0) return {};
  char text[INET6_ADDRSTRLEN] = {};
  if (inet_ntop(AF_INET6, &raw, text, sizeof(text)) == nullptr) return {};
  std::string result = text;
  if (link_local) result += "%" + std::to_string(interface_index);
  return result;
}

std::vector<DnsSdRecord> ParseRecords(PDNS_RECORD records) {
  std::vector<DnsSdRecord> parsed;
  for (PDNS_RECORD record = records; record != nullptr; record = record->pNext) {
    DnsSdRecord item;
    item.name = Utf8(record->pName);
    item.ttl = record->dwTtl;
    switch (record->wType) {
      case DNS_TYPE_PTR:
        item.type = DnsSdRecord::Type::kPtr;
        item.target = Utf8(record->Data.PTR.pNameHost);
        break;
      case DNS_TYPE_SRV:
        item.type = DnsSdRecord::Type::kSrv;
        item.target = Utf8(record->Data.SRV.pNameTarget);
        item.port = record->Data.SRV.wPort;
        break;
      case DNS_TYPE_TEXT:
        item.type = DnsSdRecord::Type::kTxt;
        for (DWORD index = 0; index < record->Data.TXT.dwStringCount; ++index) {
          item.txt.push_back(Utf8(record->Data.TXT.pStringArray[index]));
        }
        break;
      case DNS_TYPE_A:
        item.type = DnsSdRecord::Type::kAddress;
        item.address = Ipv4Text(record->Data.A.IpAddress);
        break;
      case DNS_TYPE_AAAA:
        item.type = DnsSdRecord::Type::kAddress;
        item.address = Ipv6Text(record->Data.AAAA.Ip6Address, 0);
        break;
      default:
        continue;
    }
    if (item.type == DnsSdRecord::Type::kAddress && item.address.empty()) continue;
    parsed.push_back(std::move(item));
  }
  return parsed;
}

std::wstring LocalHostName() {
  wchar_t buffer[256] = {};
  DWORD size = static_cast<DWORD>(std::size(buffer));
  if (!GetComputerNameExW(ComputerNameDnsHostname, buffer, &size) || size == 0) return L"kelpie.local";
  return std::wstring(buffer, size) + L".local";
}

// The DNS APIs get an integer context, never a pointer: a late callback looks
// its owner up here and finds nothing once the owner is gone.
class Contexts {
 public:
  template <typename State>
  static PVOID Add(const std::shared_ptr<State>& state, std::uint64_t* id) {
    std::lock_guard<std::mutex> lock(mutex());
    *id = ++next();
    owners()[*id] = state;
    return reinterpret_cast<PVOID>(static_cast<std::uintptr_t>(*id));
  }
  static void Remove(std::uint64_t id) {
    std::lock_guard<std::mutex> lock(mutex());
    owners().erase(id);
  }
  template <typename State>
  static std::shared_ptr<State> Find(PVOID context) {
    std::lock_guard<std::mutex> lock(mutex());
    const auto found = owners().find(static_cast<std::uint64_t>(reinterpret_cast<std::uintptr_t>(context)));
    return found == owners().end() ? nullptr : std::static_pointer_cast<State>(found->second.lock());
  }

 private:
  static std::mutex& mutex() { static std::mutex value; return value; }
  static std::uint64_t& next() { static std::uint64_t value = 0; return value; }
  static std::map<std::uint64_t, std::weak_ptr<void>>& owners() {
    static std::map<std::uint64_t, std::weak_ptr<void>> value;
    return value;
  }
};

}  // namespace

struct SyncDiscoveryWindows::State : std::enable_shared_from_this<State> {
  enum class Phase { kRegistering, kRegistered, kFailed, kDeregistering, kDone };
  struct Registration {
    std::uint64_t id = 0;
    DNS_SERVICE_REGISTER_REQUEST request{};
    PDNS_SERVICE_INSTANCE instance = nullptr;
    std::wstring host;
    std::wstring full_name;
    Phase phase = Phase::kRegistering;
    // Nobody waits any more: the final callback withdraws and frees it.
    bool orphaned = false;
    ~Registration() {
      if (instance != nullptr) Api().free_instance(instance);
    }
  };
  struct Advert {
    int port = 0;
    SyncTxt txt;
  };
  struct Resolve {
    std::uint64_t id = 0;
    std::wstring name;
    DNS_SERVICE_CANCEL cancel{};
  };

  // Guarded by queue_mutex; the facade takes it out (and joins it) on destruction.
  std::mutex queue_mutex;
  std::unique_ptr<SyncSerialQueue> queue = std::make_unique<SyncSerialQueue>();
  SyncPeerDelivery delivery{[this](std::function<void()> task) { PostAt(Clock::now(), std::move(task)); }};

  std::mutex mutex;
  std::condition_variable settled;
  std::optional<Advert> wanted;
  std::map<std::uint64_t, std::unique_ptr<Registration>> registrations;
  std::uint64_t current = 0;
  std::chrono::seconds retry_delay{0};
  std::uint64_t retry_token = 0;

  std::uint64_t browse_generation = 0;  // 0: not browsing
  std::uint64_t browse_id = 0;
  DNS_SERVICE_CANCEL browse_cancel{};
  std::uint64_t refresh_token = 0;
  DnsSdBrowseCache cache{kServiceDomain};
  SyncPeerTable table;
  std::map<std::string, Resolve> resolves;  // by lower-case full name

  ~State();

  void PostAt(Clock::time_point when, std::function<void()> task);
  std::unique_ptr<SyncSerialQueue> TakeQueue();
  bool StartRegistration(const Advert& advert);
  void Retire(std::uint64_t id);
  void RetireCurrent();
  void OnRegistered(std::uint64_t id, DWORD status);
  void ScheduleRetry(std::uint64_t id);

  bool StartBrowse();
  void CancelBrowse();
  void ScheduleRefresh();
  void OnBrowse(std::uint64_t id, DWORD status, std::vector<DnsSdRecord> records);
  void OnResolved(std::uint64_t id, const std::string& key, PDNS_SERVICE_INSTANCE instance);
  void Publish(const DnsSdBrowseCache::Result& result);
  void StartResolve(const std::string& key);
  void CancelResolves();
};

namespace {

using State = SyncDiscoveryWindows::State;

void WINAPI OnRegisterComplete(DWORD status, PVOID context, PDNS_SERVICE_INSTANCE instance) {
  const auto state = Contexts::Find<State>(context);
  const auto id = static_cast<std::uint64_t>(reinterpret_cast<std::uintptr_t>(context));
  // Windows hands back its own copy of the instance; the one we built stays
  // with the registration until it is withdrawn.
  bool own = false;
  if (state) {
    std::lock_guard<std::mutex> lock(state->mutex);
    const auto found = state->registrations.find(id);
    own = found != state->registrations.end() && found->second->instance == instance;
  }
  if (instance != nullptr && !own) Api().free_instance(instance);
  if (state) state->OnRegistered(id, status);
}

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

void SyncDiscoveryWindows::State::PostAt(Clock::time_point when, std::function<void()> task) {
  std::lock_guard<std::mutex> lock(queue_mutex);
  if (queue) queue->PostAt(when, std::move(task));
}

std::unique_ptr<SyncSerialQueue> SyncDiscoveryWindows::State::TakeQueue() {
  std::lock_guard<std::mutex> lock(queue_mutex);
  return std::move(queue);
}

SyncDiscoveryWindows::State::~State() {
  // The owner already withdrew everything; whatever is still waiting for the
  // OS is kept alive for the process, since Windows may still read it.
  static std::mutex graveyard_mutex;
  static std::vector<std::unique_ptr<Registration>> graveyard;
  std::lock_guard<std::mutex> lock(graveyard_mutex);
  for (auto& [id, registration] : registrations) graveyard.push_back(std::move(registration));
}

bool SyncDiscoveryWindows::State::StartRegistration(const Advert& advert) {
  const std::string name = SyncInstanceName(advert.txt);
  const auto wide_name = utf::Utf8ToWide(name + "." + kServiceDomain);
  if (name.empty() || !wide_name) return false;

  std::vector<std::wstring> keys;
  std::vector<std::wstring> values;
  for (const auto& entry : EncodeSyncTxt(advert.txt)) {
    const auto split = entry.find('=');
    const auto key = utf::Utf8ToWide(entry.substr(0, split));
    const auto value = utf::Utf8ToWide(entry.substr(split + 1));
    if (!key || !value) continue;
    keys.push_back(*key);
    values.push_back(*value);
  }
  std::vector<PCWSTR> key_pointers;
  std::vector<PCWSTR> value_pointers;
  for (std::size_t index = 0; index < keys.size(); ++index) {
    key_pointers.push_back(keys[index].c_str());
    value_pointers.push_back(values[index].c_str());
  }

  auto registration = std::make_unique<Registration>();
  registration->host = LocalHostName();
  registration->full_name = *wide_name;
  // No addresses: Windows answers for its own host name on every interface.
  registration->instance = Api().construct(
      registration->full_name.c_str(), registration->host.c_str(), nullptr, nullptr,
      static_cast<WORD>(advert.port), 0, 0, static_cast<DWORD>(key_pointers.size()),
      key_pointers.data(), value_pointers.data());
  if (registration->instance == nullptr) {
    Log("construct failed", GetLastError());
    return false;
  }
  registration->request.Version = DNS_QUERY_REQUEST_VERSION1;
  registration->request.InterfaceIndex = 0;
  registration->request.pServiceInstance = registration->instance;
  registration->request.pRegisterCompletionCallback = OnRegisterComplete;
  registration->request.pQueryContext = Contexts::Add(shared_from_this(), &registration->id);
  registration->request.unicastEnabled = FALSE;

  const std::uint64_t id = registration->id;
  DNS_SERVICE_REGISTER_REQUEST* request = &registration->request;
  {
    std::lock_guard<std::mutex> lock(mutex);
    cache.SetOwnInstance(name + "." + kServiceDomain);
    current = id;
    registrations[id] = std::move(registration);
  }
  // Native calls run without our lock: a completion may arrive on any thread.
  const DWORD status = Api().register_service(request, nullptr);
  if (status == DNS_REQUEST_PENDING) return true;
  Log("register rejected", status);
  std::lock_guard<std::mutex> lock(mutex);
  registrations.erase(id);
  if (current == id) current = 0;
  Contexts::Remove(id);
  return false;
}

void SyncDiscoveryWindows::State::OnRegistered(std::uint64_t id, DWORD status) {
  bool withdraw = false;
  bool failed = false;
  DNS_SERVICE_REGISTER_REQUEST* request = nullptr;
  {
    std::lock_guard<std::mutex> lock(mutex);
    const auto found = registrations.find(id);
    if (found == registrations.end()) return;
    auto& registration = *found->second;
    if (registration.phase == Phase::kRegistering) {
      if (status != ERROR_SUCCESS) {
        registration.phase = Phase::kFailed;
        failed = id == current && !registration.orphaned;
      } else if (registration.orphaned) {
        // Stopped while registering: withdraw it now that it exists.
        registration.phase = Phase::kDeregistering;
        withdraw = true;
        request = &registration.request;
      } else {
        registration.phase = Phase::kRegistered;
        retry_delay = std::chrono::seconds(0);
      }
    } else if (registration.phase == Phase::kDeregistering) {
      registration.phase = Phase::kDone;
    }
    if (registration.orphaned && (registration.phase == Phase::kDone || registration.phase == Phase::kFailed)) {
      registrations.erase(found);
      Contexts::Remove(id);
    }
  }
  settled.notify_all();
  if (status != ERROR_SUCCESS) Log("registration completed with error", status);
  if (withdraw && Api().deregister_service(request, nullptr) != DNS_REQUEST_PENDING) {
    std::lock_guard<std::mutex> lock(mutex);
    registrations.erase(id);
    Contexts::Remove(id);
  }
  if (failed) ScheduleRetry(id);
}

void SyncDiscoveryWindows::State::ScheduleRetry(std::uint64_t id) {
  std::uint64_t token = 0;
  std::chrono::seconds delay{};
  {
    std::lock_guard<std::mutex> lock(mutex);
    retry_delay = retry_delay.count() == 0 ? std::chrono::duration_cast<std::chrono::seconds>(kRetryFirst)
                                           : std::min(retry_delay * 2, std::chrono::duration_cast<std::chrono::seconds>(kRetryMax));
    delay = retry_delay;
    token = ++retry_token;
  }
  std::weak_ptr<State> weak = shared_from_this();
  PostAt(Clock::now() + delay, [weak, id, token] {
    const auto state = weak.lock();
    if (!state) return;
    std::optional<Advert> advert;
    {
      std::lock_guard<std::mutex> lock(state->mutex);
      if (token != state->retry_token || state->current != id || !state->wanted) return;
      advert = state->wanted;
    }
    state->Retire(id);
    if (!state->StartRegistration(*advert)) state->ScheduleRetry(0);
  });
}

void SyncDiscoveryWindows::State::Retire(std::uint64_t id) {
  std::unique_lock<std::mutex> lock(mutex);
  if (current == id) current = 0;
  auto found = registrations.find(id);
  if (found == registrations.end()) return;
  Registration* registration = found->second.get();
  const auto deadline = Clock::now() + kStopWait;
  // Let a registration in flight settle so its goodbye can be sent.
  settled.wait_until(lock, deadline, [&] {
    return registrations.count(id) == 0 || registration->phase != Phase::kRegistering;
  });
  if (registrations.count(id) == 0) return;
  if (registration->phase == Phase::kRegistering) {
    registration->orphaned = true;
    return;
  }
  if (registration->phase == Phase::kDeregistering) {
    // Another caller is already withdrawing it; wait for that below.
  } else if (registration->phase == Phase::kRegistered) {
    registration->phase = Phase::kDeregistering;
    lock.unlock();
    const DWORD status = Api().deregister_service(&registration->request, nullptr);
    lock.lock();
    if (status != DNS_REQUEST_PENDING) {
      Log("deregister rejected", status);
      registration->phase = Phase::kDone;
    }
  }
  settled.wait_until(lock, deadline + kStopWait, [&] {
    return registrations.count(id) == 0 || registration->phase == Phase::kDone ||
           registration->phase == Phase::kFailed;
  });
  if (registrations.count(id) == 0) return;
  if (registration->phase == Phase::kDone || registration->phase == Phase::kFailed) {
    registrations.erase(id);
    Contexts::Remove(id);
  } else {
    registration->orphaned = true;
  }
}

void SyncDiscoveryWindows::State::RetireCurrent() {
  std::uint64_t id = 0;
  {
    std::lock_guard<std::mutex> lock(mutex);
    id = current;
    ++retry_token;
    retry_delay = std::chrono::seconds(0);
  }
  if (id != 0) Retire(id);
}

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

bool SyncDiscoveryWindows::Advertise(int port, const std::map<std::string, std::string>& txt) {
  if (!ApiAvailable() || port <= 0 || port > 65535 || SyncInstanceName(txt).empty()) return false;
  {
    std::lock_guard<std::mutex> lock(state_->mutex);
    if (state_->wanted && state_->wanted->port == port && state_->wanted->txt == txt && state_->current != 0) {
      return true;
    }
  }
  state_->RetireCurrent();
  State::Advert advert{port, txt};
  {
    std::lock_guard<std::mutex> lock(state_->mutex);
    state_->wanted = advert;
  }
  if (state_->StartRegistration(advert)) return true;
  std::lock_guard<std::mutex> lock(state_->mutex);
  state_->wanted.reset();
  return false;
}

void SyncDiscoveryWindows::UpdateTxt(const std::map<std::string, std::string>& txt) {
  std::optional<State::Advert> advert;
  {
    std::lock_guard<std::mutex> lock(state_->mutex);
    if (!state_->wanted || state_->wanted->txt == txt || SyncInstanceName(txt).empty()) return;
    state_->wanted->txt = txt;
    advert = state_->wanted;
  }
  // Windows has no in-place TXT update: withdraw, then register the new record.
  state_->RetireCurrent();
  if (!state_->StartRegistration(*advert)) state_->ScheduleRetry(0);
}

void SyncDiscoveryWindows::StopAdvertising() {
  {
    std::lock_guard<std::mutex> lock(state_->mutex);
    state_->wanted.reset();
  }
  state_->RetireCurrent();
  std::lock_guard<std::mutex> lock(state_->mutex);
  state_->cache.SetOwnInstance({});
}

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
