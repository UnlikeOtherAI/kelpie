// GetAdaptersAddresses interface enumeration. Eligible adapters are up,
// Ethernet (IF_TYPE_ETHERNET_CSMACD) or Wi-Fi (IF_TYPE_IEEE80211), carry no
// tunnel type and are hardware interfaces according to GetIfEntry2. That
// excludes VPN clients (WireGuard, TAP and most others present themselves as
// virtual), Hyper-V and other virtual switches, and cellular (WWAN) adapters.
#include <winsock2.h>
#include <ws2tcpip.h>
#include <iphlpapi.h>
#include <netioapi.h>

#include <cstring>
#include <string>
#include <vector>

#include "sync_net.h"

namespace kelpie::desktop_sync {
namespace {

bool IsHardware(NET_LUID luid) {
  MIB_IF_ROW2 row{};
  row.InterfaceLuid = luid;
  if (GetIfEntry2(&row) != NO_ERROR) return false;
  return row.InterfaceAndOperStatusFlags.HardwareInterface != FALSE;
}

}  // namespace

bool PtonV4(const std::string& text, std::uint8_t* out4) { return inet_pton(AF_INET, text.c_str(), out4) == 1; }
bool PtonV6(const std::string& text, std::uint8_t* out16) { return inet_pton(AF_INET6, text.c_str(), out16) == 1; }

std::uint32_t ResolveZone(const std::string& zone) {
  if (zone.empty() || zone.find_first_not_of("0123456789") != std::string::npos) return 0;
  try { return static_cast<std::uint32_t>(std::stoul(zone)); } catch (...) { return 0; }
}

std::vector<InterfaceAddress> EnumerateInterfaces() {
  std::vector<InterfaceAddress> out;
  ULONG size = 16 * 1024;
  std::vector<unsigned char> buffer;
  ULONG result = ERROR_BUFFER_OVERFLOW;
  const ULONG flags = GAA_FLAG_SKIP_ANYCAST | GAA_FLAG_SKIP_MULTICAST | GAA_FLAG_SKIP_DNS_SERVER;
  for (int attempt = 0; attempt < 3 && result == ERROR_BUFFER_OVERFLOW; ++attempt) {
    buffer.resize(size);
    result = GetAdaptersAddresses(AF_UNSPEC, flags, nullptr,
                                  reinterpret_cast<IP_ADAPTER_ADDRESSES*>(buffer.data()), &size);
  }
  if (result != NO_ERROR) return out;
  for (auto* adapter = reinterpret_cast<IP_ADAPTER_ADDRESSES*>(buffer.data()); adapter != nullptr;
       adapter = adapter->Next) {
    const bool kind = adapter->IfType == IF_TYPE_ETHERNET_CSMACD || adapter->IfType == IF_TYPE_IEEE80211;
    const bool eligible = adapter->OperStatus == IfOperStatusUp && kind &&
                          adapter->TunnelType == TUNNEL_TYPE_NONE && IsHardware(adapter->Luid);
    for (auto* unicast = adapter->FirstUnicastAddress; unicast != nullptr; unicast = unicast->Next) {
      const sockaddr* address = unicast->Address.lpSockaddr;
      if (address == nullptr) continue;
      InterfaceAddress entry;
      entry.prefix = unicast->OnLinkPrefixLength;
      entry.eligible = eligible;
      if (address->sa_family == AF_INET) {
        std::memcpy(entry.address.bytes.data(), &reinterpret_cast<const sockaddr_in*>(address)->sin_addr, 4);
        entry.index = adapter->IfIndex;
      } else if (address->sa_family == AF_INET6) {
        const auto* v6 = reinterpret_cast<const sockaddr_in6*>(address);
        entry.address.v6 = true;
        std::memcpy(entry.address.bytes.data(), &v6->sin6_addr, 16);
        entry.address.scope = v6->sin6_scope_id;
        entry.index = adapter->Ipv6IfIndex;
      } else {
        continue;
      }
      out.push_back(entry);
    }
  }
  return out;
}

}  // namespace kelpie::desktop_sync
