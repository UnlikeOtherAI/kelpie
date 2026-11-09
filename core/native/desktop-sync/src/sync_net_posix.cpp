// getifaddrs interface enumeration. Linux decides "physical" from sysfs: a
// real NIC has /sys/class/net/<name>/device, while tun/tap, WireGuard, PPP,
// bridges, veth and Docker interfaces do not; WWAN modems are excluded by
// their uevent DEVTYPE. macOS (developer builds only) accepts en* interfaces.
#include <arpa/inet.h>
#include <ifaddrs.h>
#include <net/if.h>
#include <netinet/in.h>
#include <sys/socket.h>

#include <cstring>
#include <fstream>
#include <iterator>
#include <string>

#include "sync_net.h"

namespace kelpie::desktop_sync {
namespace {

int PrefixLength(const sockaddr* mask) {
  if (mask == nullptr) return 0;
  const std::uint8_t* bytes = nullptr;
  std::size_t size = 0;
  if (mask->sa_family == AF_INET) {
    bytes = reinterpret_cast<const std::uint8_t*>(&reinterpret_cast<const sockaddr_in*>(mask)->sin_addr);
    size = 4;
  } else if (mask->sa_family == AF_INET6) {
    bytes = reinterpret_cast<const std::uint8_t*>(&reinterpret_cast<const sockaddr_in6*>(mask)->sin6_addr);
    size = 16;
  }
  int prefix = 0;
  for (std::size_t i = 0; i < size; ++i) {
    for (int bit = 7; bit >= 0; --bit) {
      if ((bytes[i] >> bit) & 1) ++prefix; else return prefix;
    }
  }
  return prefix;
}

bool HasVirtualName(const std::string& name) {
  static const char* const kPrefixes[] = {"tun", "tap", "wg", "ppp", "tailscale", "zt", "utun", "ipsec", "vpn",
                                          "docker", "veth", "br-", "virbr", "vmnet", "vboxnet", "wwan", "rmnet",
                                          "awdl", "llw", "bridge", "gif", "stf", "anpi"};
  for (const char* prefix : kPrefixes) {
    if (name.rfind(prefix, 0) == 0) return true;
  }
  return false;
}

#if defined(__linux__)
std::string ReadFile(const std::string& path) {
  std::ifstream input(path);
  return std::string(std::istreambuf_iterator<char>(input), std::istreambuf_iterator<char>());
}

bool IsPhysical(const std::string& name) {
  const std::string base = "/sys/class/net/" + name;
  std::ifstream device(base + "/device/uevent");
  if (!device) return false;
  if (ReadFile(base + "/uevent").find("DEVTYPE=wwan") != std::string::npos) return false;
  // ARPHRD_ETHER (1) covers wired Ethernet and Wi-Fi.
  const std::string type = ReadFile(base + "/type");
  return type == "1\n" || type == "1";
}
#else
bool IsPhysical(const std::string& name) { return name.rfind("en", 0) == 0; }
#endif

}  // namespace

bool PtonV4(const std::string& text, std::uint8_t* out4) { return inet_pton(AF_INET, text.c_str(), out4) == 1; }
bool PtonV6(const std::string& text, std::uint8_t* out16) { return inet_pton(AF_INET6, text.c_str(), out16) == 1; }

std::uint32_t ResolveZone(const std::string& zone) {
  if (zone.find_first_not_of("0123456789") == std::string::npos) {
    try { return static_cast<std::uint32_t>(std::stoul(zone)); } catch (...) { return 0; }
  }
  return if_nametoindex(zone.c_str());
}

std::vector<InterfaceAddress> EnumerateInterfaces() {
  std::vector<InterfaceAddress> out;
  ifaddrs* list = nullptr;
  if (getifaddrs(&list) != 0) return out;
  for (ifaddrs* item = list; item != nullptr; item = item->ifa_next) {
    if (item->ifa_addr == nullptr || item->ifa_name == nullptr) continue;
    const int family = item->ifa_addr->sa_family;
    if (family != AF_INET && family != AF_INET6) continue;
    InterfaceAddress entry;
    entry.index = if_nametoindex(item->ifa_name);
    if (family == AF_INET) {
      std::memcpy(entry.address.bytes.data(), &reinterpret_cast<sockaddr_in*>(item->ifa_addr)->sin_addr, 4);
    } else {
      const auto* v6 = reinterpret_cast<sockaddr_in6*>(item->ifa_addr);
      entry.address.v6 = true;
      std::memcpy(entry.address.bytes.data(), &v6->sin6_addr, 16);
      entry.address.scope = v6->sin6_scope_id;
    }
    entry.prefix = PrefixLength(item->ifa_netmask);
    const unsigned flags = item->ifa_flags;
    const std::string name = item->ifa_name;
    entry.eligible = (flags & IFF_UP) && (flags & IFF_RUNNING) && !(flags & IFF_LOOPBACK) &&
                     !(flags & IFF_POINTOPOINT) && !HasVirtualName(name) && IsPhysical(name);
    out.push_back(entry);
  }
  freeifaddrs(list);
  return out;
}

}  // namespace kelpie::desktop_sync
