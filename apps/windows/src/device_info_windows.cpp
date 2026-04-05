#include "device_info_windows.h"

#include <fstream>
#include <random>
#include <sstream>
#include <vector>

#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <winsock2.h>
#include <ws2tcpip.h>
#include <iphlpapi.h>
#include <rpc.h>
#include <winreg.h>
#include <winternl.h>

namespace kelpie::windows {
namespace {

std::string WideToUtf8(const std::wstring& value) {
  if (value.empty()) {
    return {};
  }
  const int size = WideCharToMultiByte(CP_UTF8, 0, value.c_str(), -1, nullptr, 0, nullptr, nullptr);
  std::string output(static_cast<std::size_t>(size > 0 ? size - 1 : 0), '\0');
  if (size > 1) {
    WideCharToMultiByte(CP_UTF8, 0, value.c_str(), -1, output.data(), size - 1, nullptr, nullptr);
  }
  return output;
}

std::string ReadOrCreateDeviceId(const std::filesystem::path& profile_dir) {
  const auto path = profile_dir / "device-id";
  if (std::ifstream input(path); input.good()) {
    std::string value;
    std::getline(input, value);
    if (!value.empty()) {
      return value;
    }
  }

  UUID uuid{};
  UuidCreate(&uuid);
  RPC_CSTR string_value = nullptr;
  UuidToStringA(&uuid, &string_value);
  std::string generated(reinterpret_cast<char*>(string_value));
  RpcStringFreeA(&string_value);

  std::ofstream output(path, std::ios::trunc);
  output << generated;
  return generated;
}

std::string ComputerName() {
  wchar_t buffer[MAX_COMPUTERNAME_LENGTH + 1]{};
  DWORD size = MAX_COMPUTERNAME_LENGTH + 1;
  if (GetComputerNameExW(ComputerNameDnsHostname, buffer, &size)) {
    return WideToUtf8(buffer);
  }
  return "Windows";
}

std::string RegistryString(HKEY root, const wchar_t* path, const wchar_t* value_name, const char* fallback) {
  HKEY key = nullptr;
  if (RegOpenKeyExW(root, path, 0, KEY_READ, &key) != ERROR_SUCCESS) {
    return fallback;
  }
  wchar_t buffer[256]{};
  DWORD type = REG_SZ;
  DWORD size = sizeof(buffer);
  const LONG status = RegQueryValueExW(key, value_name, nullptr, &type,
                                       reinterpret_cast<LPBYTE>(buffer), &size);
  RegCloseKey(key);
  return status == ERROR_SUCCESS ? WideToUtf8(buffer) : fallback;
}

std::string FirstIpv4Address() {
  ULONG buffer_size = 15 * 1024;
  std::vector<BYTE> buffer(buffer_size);
  auto* addresses = reinterpret_cast<IP_ADAPTER_ADDRESSES*>(buffer.data());
  if (GetAdaptersAddresses(AF_INET, GAA_FLAG_SKIP_ANYCAST | GAA_FLAG_SKIP_MULTICAST |
                                       GAA_FLAG_SKIP_DNS_SERVER,
                           nullptr, addresses, &buffer_size) != NO_ERROR) {
    return "0.0.0.0";
  }

  for (auto* adapter = addresses; adapter != nullptr; adapter = adapter->Next) {
    if (adapter->IfType == IF_TYPE_SOFTWARE_LOOPBACK) {
      continue;
    }
    for (auto* unicast = adapter->FirstUnicastAddress; unicast != nullptr; unicast = unicast->Next) {
      char host[NI_MAXHOST]{};
      if (getnameinfo(unicast->Address.lpSockaddr, static_cast<socklen_t>(unicast->Address.iSockaddrLength),
                      host, sizeof(host), nullptr, 0, NI_NUMERICHOST) == 0) {
        return host;
      }
    }
  }
  return "0.0.0.0";
}

std::string OsVersion() {
  using RtlGetVersionPtr = LONG(WINAPI*)(PRTL_OSVERSIONINFOW);
  HMODULE module = GetModuleHandleW(L"ntdll.dll");
  if (module == nullptr) {
    return "unknown";
  }
  auto function = reinterpret_cast<RtlGetVersionPtr>(GetProcAddress(module, "RtlGetVersion"));
  if (function == nullptr) {
    return "unknown";
  }
  RTL_OSVERSIONINFOW info{};
  info.dwOSVersionInfoSize = sizeof(info);
  if (function(&info) != 0) {
    return "unknown";
  }
  std::ostringstream stream;
  stream << info.dwMajorVersion << '.' << info.dwMinorVersion << '.' << info.dwBuildNumber;
  return stream.str();
}

}  // namespace

nlohmann::json ToJson(const DeviceInfo& device_info) {
  return {
      {"id", device_info.id},
      {"name", device_info.name},
      {"model", device_info.model},
      {"platform", device_info.platform},
      {"engine", device_info.engine},
      {"ip", device_info.ip_address},
      {"os", device_info.os_version},
      {"version", device_info.app_version},
      {"width", device_info.width},
      {"height", device_info.height},
      {"port", device_info.port},
      {"memory", {{"total", device_info.total_memory_bytes}, {"available", device_info.available_memory_bytes}}},
  };
}

StringMap ToTxtRecord(const DeviceInfo& device_info) {
  return {
      {"id", device_info.id},
      {"name", device_info.name},
      {"model", device_info.model},
      {"platform", device_info.platform},
      {"engine", device_info.engine},
      {"width", std::to_string(device_info.width)},
      {"height", std::to_string(device_info.height)},
      {"port", std::to_string(device_info.port)},
      {"version", device_info.app_version},
  };
}

DeviceInfoWindows::DeviceInfoWindows(std::filesystem::path profile_dir)
    : profile_dir_(std::move(profile_dir)) {}

void DeviceInfoWindows::SetProfileDir(std::filesystem::path profile_dir) {
  profile_dir_ = std::move(profile_dir);
}

DeviceInfo DeviceInfoWindows::Collect(int port, int width, int height, const std::string& app_version) const {
  MEMORYSTATUSEX status{};
  status.dwLength = sizeof(status);
  GlobalMemoryStatusEx(&status);

  DeviceInfo info;
  info.id = ReadOrCreateDeviceId(profile_dir_);
  info.name = ComputerName();
  info.model = RegistryString(HKEY_LOCAL_MACHINE,
                              L"HARDWARE\\DESCRIPTION\\System\\BIOS",
                              L"SystemProductName",
                              "PC");
  info.ip_address = FirstIpv4Address();
  info.os_version = OsVersion();
  info.app_version = app_version;
  info.total_memory_bytes = status.ullTotalPhys;
  info.available_memory_bytes = status.ullAvailPhys;
  info.width = width;
  info.height = height;
  info.port = port;
  return info;
}

}  // namespace kelpie::windows
