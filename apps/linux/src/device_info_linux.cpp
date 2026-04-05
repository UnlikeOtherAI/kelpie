#include "device_info_linux.h"

#include <ifaddrs.h>
#include <netdb.h>
#include <net/if.h>
#include <sys/utsname.h>
#include <unistd.h>

#include <filesystem>
#include <fstream>
#include <sstream>

namespace kelpie::linuxapp {
namespace {

std::string Trim(std::string value) {
  const auto start = value.find_first_not_of(" \t\r\n");
  if (start == std::string::npos) {
    return std::string();
  }
  const auto end = value.find_last_not_of(" \t\r\n");
  return value.substr(start, end - start + 1);
}

std::string ReadFile(const std::filesystem::path& path) {
  std::ifstream stream(path);
  if (!stream.good()) {
    return std::string();
  }
  std::ostringstream buffer;
  buffer << stream.rdbuf();
  return buffer.str();
}

std::string GeneratePseudoUuid() {
  std::ifstream source("/proc/sys/kernel/random/uuid");
  std::string uuid;
  std::getline(source, uuid);
  return Trim(uuid);
}

std::string EnsureDeviceId(const std::filesystem::path& profile_dir) {
  std::filesystem::create_directories(profile_dir);
  const std::filesystem::path path = profile_dir / "device-id";
  const std::string existing = Trim(ReadFile(path));
  if (!existing.empty()) {
    return existing;
  }

  const std::string generated = GeneratePseudoUuid();
  std::ofstream stream(path, std::ios::trunc);
  stream << generated;
  return generated;
}

std::string Hostname() {
  char buffer[256] = {};
  if (gethostname(buffer, sizeof(buffer) - 1) != 0) {
    return "Kelpie Linux";
  }
  return buffer;
}

std::string Architecture() {
  utsname info{};
  if (uname(&info) != 0) {
    return "unknown";
  }
  return info.machine;
}

std::string Model() {
  const std::string model = Trim(ReadFile("/sys/devices/virtual/dmi/id/product_name"));
  return model.empty() ? "Linux Desktop" : model;
}

std::pair<std::string, std::string> OperatingSystem() {
  std::ifstream stream("/etc/os-release");
  std::string line;
  std::string pretty_name;
  while (std::getline(stream, line)) {
    if (line.rfind("PRETTY_NAME=", 0) == 0) {
      pretty_name = line.substr(12, line.size() - 13);
      break;
    }
  }
  return pretty_name.empty() ? std::make_pair(std::string("Linux"), std::string("unknown"))
                             : std::make_pair(std::string("Linux"), pretty_name);
}

std::pair<std::int64_t, std::int64_t> MemoryInfo() {
  std::ifstream stream("/proc/meminfo");
  std::string label;
  std::int64_t value = 0;
  std::string unit;
  std::int64_t total = 0;
  std::int64_t available = 0;
  while (stream >> label >> value >> unit) {
    if (label == "MemTotal:") {
      total = value / 1024;
    } else if (label == "MemAvailable:") {
      available = value / 1024;
    }
  }
  return {total, available};
}

std::string IpAddress() {
  ifaddrs* interfaces = nullptr;
  if (getifaddrs(&interfaces) != 0) {
    return std::string();
  }

  std::string result;
  for (ifaddrs* current = interfaces; current != nullptr; current = current->ifa_next) {
    if (current->ifa_addr == nullptr || current->ifa_addr->sa_family != AF_INET) {
      continue;
    }
    if ((current->ifa_flags & IFF_LOOPBACK) != 0) {
      continue;
    }

    char host[NI_MAXHOST] = {};
    const int ok = getnameinfo(current->ifa_addr,
                               sizeof(sockaddr_in),
                               host,
                               sizeof(host),
                               nullptr,
                               0,
                               NI_NUMERICHOST);
    if (ok == 0) {
      result = host;
      break;
    }
  }

  freeifaddrs(interfaces);
  return result;
}

}  // namespace

DeviceInfoLinux::DeviceInfoLinux(std::string profile_dir)
    : profile_dir_(std::move(profile_dir)) {}

DeviceInfoSnapshot DeviceInfoLinux::Collect() const {
  const auto [os_name, os_version] = OperatingSystem();
  const auto [total_memory, available_memory] = MemoryInfo();
  return DeviceInfoSnapshot{
      EnsureDeviceId(profile_dir_),
      Hostname(),
      Model(),
      "Generic",
      "linux",
      "chromium",
      os_name,
      os_version,
      Architecture(),
      IpAddress(),
      total_memory,
      available_memory,
  };
}

nlohmann::json DeviceInfoLinux::ToJson(const DeviceInfoSnapshot& snapshot,
                                       int port,
                                       int width,
                                       int height,
                                       bool mdns_active,
                                       bool http_active,
                                       const std::string& mdns_name,
                                       const std::string& version,
                                       std::int64_t uptime_seconds) const {
  using json = nlohmann::json;

  const json ip_val = snapshot.ip.empty() ? json(nullptr) : json(snapshot.ip);
  const json mdns_val = mdns_name.empty() ? json(nullptr) : json(mdns_name);
  const json engine_version = KELPIE_LINUX_HAS_CEF ? json("embedded") : json(nullptr);

  const char* lang_env = std::getenv("LANG");
  const json locale_val = lang_env != nullptr ? json(lang_env) : json(nullptr);
  const char* tz_env = std::getenv("TZ");
  const json tz_val = tz_env != nullptr ? json(tz_env) : json(nullptr);

  json result;
  result["device"] = {
      {"id", snapshot.id},
      {"name", snapshot.name},
      {"model", snapshot.model},
      {"manufacturer", snapshot.manufacturer},
      {"platform", snapshot.platform},
      {"osName", snapshot.os_name},
      {"osVersion", snapshot.os_version},
      {"architecture", snapshot.architecture},
      {"isSimulator", false},
      {"isTablet", false}};
  result["display"] = {
      {"width", width},
      {"height", height},
      {"physicalWidth", width},
      {"physicalHeight", height},
      {"devicePixelRatio", 1.0},
      {"orientation", width >= height ? "landscape" : "portrait"},
      {"refreshRate", nullptr},
      {"screenDiagonal", nullptr},
      {"safeAreaInsets", {{"top", 0}, {"bottom", 0}, {"left", 0}, {"right", 0}}}};
  result["network"] = {
      {"ip", ip_val},
      {"port", port},
      {"mdnsName", mdns_val},
      {"networkType", nullptr},
      {"ssid", nullptr}};
  result["browser"] = {
      {"engine", snapshot.engine},
      {"engineVersion", engine_version},
      {"userAgent", "Kelpie Linux Chromium"},
      {"viewportWidth", width},
      {"viewportHeight", height}};
  result["app"] = {
      {"version", version},
      {"build", "linux"},
      {"httpServerActive", http_active},
      {"mcpServerActive", false},
      {"mdnsActive", mdns_active},
      {"uptime", uptime_seconds}};
  result["system"] = {
      {"locale", locale_val},
      {"timezone", tz_val},
      {"batteryLevel", nullptr},
      {"batteryCharging", nullptr},
      {"thermalState", nullptr},
      {"availableMemory", snapshot.available_memory},
      {"totalMemory", snapshot.total_memory}};
  return result;
}

}  // namespace kelpie::linuxapp
