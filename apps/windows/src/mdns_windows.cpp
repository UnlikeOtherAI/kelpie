#include "mdns_windows.h"

#include <sstream>

#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>

#if defined(_WIN32) && __has_include(<windns.h>)
#include <windns.h>
#endif

#if defined(_WIN32) && __has_include(<dns_sd.h>)
#include <dns_sd.h>
#endif

namespace mollotov::windows {
namespace {

std::wstring Utf8ToWide(const std::string& value) {
  if (value.empty()) {
    return {};
  }
  const int size = MultiByteToWideChar(CP_UTF8, 0, value.c_str(), -1, nullptr, 0);
  std::wstring output(static_cast<std::size_t>(size > 0 ? size - 1 : 0), L'\0');
  if (size > 1) {
    MultiByteToWideChar(CP_UTF8, 0, value.c_str(), -1, output.data(), size - 1);
  }
  return output;
}

std::vector<BYTE> BuildTxtRecord(const StringMap& txt_records) {
  std::vector<BYTE> bytes;
  for (const auto& [key, value] : txt_records) {
    const std::string pair = key + "=" + value;
    bytes.push_back(static_cast<BYTE>(pair.size()));
    bytes.insert(bytes.end(), pair.begin(), pair.end());
  }
  return bytes;
}

std::vector<std::wstring> Utf8MapValues(const StringMap& values, bool keys) {
  std::vector<std::wstring> output;
  output.reserve(values.size());
  for (const auto& [key, value] : values) {
    output.push_back(Utf8ToWide(keys ? key : value));
  }
  return output;
}

}  // namespace

MdnsWindows::MdnsWindows() = default;
MdnsWindows::~MdnsWindows() {
  Stop();
}

bool MdnsWindows::Start(const MdnsRegistration& registration) {
  Stop();
  if (StartNative(registration) || StartBonjour(registration)) {
    running_ = true;
    return true;
  }
  if (last_error_.empty()) {
    SetError("mDNS unavailable: native and Bonjour registration both unavailable");
  }
  return false;
}

void MdnsWindows::Stop() {
#if defined(_WIN32) && __has_include(<windns.h>)
  if (native_instance_ != nullptr) {
    DnsServiceFreeInstance(reinterpret_cast<PDNS_SERVICE_INSTANCE>(native_instance_));
    native_instance_ = nullptr;
  }
  native_registered_ = false;
#endif
#if defined(_WIN32) && __has_include(<dns_sd.h>)
  if (bonjour_service_ != nullptr) {
    DNSServiceRefDeallocate(reinterpret_cast<DNSServiceRef>(bonjour_service_));
    bonjour_service_ = nullptr;
  }
#endif
  running_ = false;
}

bool MdnsWindows::StartNative(const MdnsRegistration& registration) {
#if defined(_WIN32) && __has_include(<windns.h>)
  // Load mDNS functions dynamically to avoid crashing on Wine or older Windows
  // where DnsServiceConstructInstance is not implemented.
  HMODULE dnsapi = GetModuleHandleW(L"DNSAPI.dll");
  if (dnsapi == nullptr) {
    dnsapi = LoadLibraryW(L"DNSAPI.dll");
  }
  if (dnsapi == nullptr) {
    SetError("DNSAPI.dll not available");
    return false;
  }

  using ConstructFn = PDNS_SERVICE_INSTANCE(WINAPI*)(PCWSTR, PCWSTR, PIP4_ADDRESS, PIP6_ADDRESS,
                                                      WORD, WORD, WORD, DWORD, PCWSTR*, PCWSTR*);
  using RegisterFn = DWORD(WINAPI*)(PDNS_SERVICE_REGISTER_REQUEST, PDNS_SERVICE_CANCEL);

  auto construct = reinterpret_cast<ConstructFn>(GetProcAddress(dnsapi, "DnsServiceConstructInstance"));
  auto reg = reinterpret_cast<RegisterFn>(GetProcAddress(dnsapi, "DnsServiceRegister"));

  if (construct == nullptr || reg == nullptr) {
    SetError("Native mDNS APIs not available (Wine or old Windows)");
    return false;
  }

  const std::wstring instance_name = Utf8ToWide(registration.instance_name);
  const auto keys = Utf8MapValues(registration.txt_records, true);
  const auto values = Utf8MapValues(registration.txt_records, false);
  std::vector<PCWSTR> key_ptrs;
  std::vector<PCWSTR> value_ptrs;
  for (const auto& key : keys) {
    key_ptrs.push_back(key.c_str());
  }
  for (const auto& value : values) {
    value_ptrs.push_back(value.c_str());
  }
  PDNS_SERVICE_INSTANCE instance =
      construct(instance_name.c_str(), L"_mollotov._tcp.local", nullptr, nullptr,
                static_cast<WORD>(registration.port), 0, 0,
                static_cast<DWORD>(key_ptrs.size()), key_ptrs.data(),
                value_ptrs.data());
  if (instance == nullptr) {
    SetError("DnsServiceConstructInstance failed");
    return false;
  }

  DNS_SERVICE_REGISTER_REQUEST request{};
  request.Version = DNS_QUERY_REQUEST_VERSION1;
  request.pServiceInstance = instance;
  const DWORD status = reg(&request, nullptr);
  if (status != DNS_REQUEST_PENDING) {
    DnsServiceFreeInstance(instance);
    std::ostringstream stream;
    stream << "DnsServiceRegister failed with status " << status;
    SetError(stream.str());
    return false;
  }

  native_instance_ = instance;
  native_registered_ = true;
  return true;
#else
  (void)registration;
  return false;
#endif
}

bool MdnsWindows::StartBonjour(const MdnsRegistration& registration) {
#if defined(_WIN32) && __has_include(<dns_sd.h>)
  const auto txt = BuildTxtRecord(registration.txt_records);
  DNSServiceRef service = nullptr;
  const DNSServiceErrorType error = DNSServiceRegister(
      &service, 0, 0, registration.instance_name.c_str(), "_mollotov._tcp", "local", nullptr,
      htons(registration.port), static_cast<uint16_t>(txt.size()), txt.data(), nullptr, nullptr);
  if (error != kDNSServiceErr_NoError) {
    std::ostringstream stream;
    stream << "DNSServiceRegister failed with error " << error;
    SetError(stream.str());
    return false;
  }

  bonjour_service_ = service;
  return true;
#else
  (void)registration;
  return false;
#endif
}

void MdnsWindows::SetError(std::string message) {
  last_error_ = std::move(message);
}

}  // namespace mollotov::windows
