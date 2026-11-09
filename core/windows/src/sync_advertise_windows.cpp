#include "sync_discovery_windows_state.h"

#include <algorithm>

#include "windows_utf.h"

namespace kelpie::windows {

using dnssd::Api;
using dnssd::Contexts;
using dnssd::Log;
using dnssd::LocalHostName;
using dnssd::Utf8;
using State = SyncDiscoveryWindows::State;
using Clock = State::Clock;

namespace {

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

}  // namespace kelpie::windows
