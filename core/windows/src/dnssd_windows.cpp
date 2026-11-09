#include "dnssd_windows.h"

#include <algorithm>
#include <cstdio>

#include "windows_utf.h"

namespace kelpie::windows::dnssd {
namespace {

template <typename Function>
void Load(HMODULE module, const char* name, Function* target) {
  *target = reinterpret_cast<Function>(reinterpret_cast<void*>(GetProcAddress(module, name)));
}

}  // namespace

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

void Log(const char* event, unsigned long code) {
  char line[160];
  std::snprintf(line, sizeof(line), "kelpie sync discovery: %s (%lu)\n", event, code);
  OutputDebugStringA(line);
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

}  // namespace kelpie::windows::dnssd
