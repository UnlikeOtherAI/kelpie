#pragma once

// Access to the Windows 10 1809+ DNS-SD API for cookie-sync discovery: the
// functions (looked up at runtime, so older Windows and Wine still start),
// record parsing and the callback context registry.

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

#include <cstdint>
#include <map>
#include <memory>
#include <mutex>
#include <string>
#include <vector>

#include "dnssd_browse_cache.h"

namespace kelpie::windows::dnssd {

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


// Looked up once; dnsapi.dll stays loaded for the life of the process.
const DnsApi& Api();

// Codes only: names, TXT values and addresses never reach the log.
void Log(const char* event, unsigned long code);

std::string Utf8(PCWSTR value);
std::string Ipv4Text(const IP4_ADDRESS& address);
// Link-local IPv6 needs a scope; without one (interface 0) it is dropped.
std::string Ipv6Text(const IP6_ADDRESS& address, DWORD interface_index);
std::vector<DnsSdRecord> ParseRecords(PDNS_RECORD records);
// "<computer>.local": Windows answers for it on every interface.
std::wstring LocalHostName();

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

}  // namespace kelpie::windows::dnssd
