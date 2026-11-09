#include "sync_net.h"

#include <algorithm>
#include <cstdio>
#include <cstring>

namespace kelpie::desktop_sync {
namespace {

bool IsV4Mapped(const std::array<std::uint8_t, 16>& bytes) {
  for (int i = 0; i < 10; ++i) if (bytes[i] != 0) return false;
  return bytes[10] == 0xff && bytes[11] == 0xff;
}

int Rank(const IpAddress& address) {
  if (IsLoopback(address)) return 4;
  if (!address.v6) return IsLinkLocal(address) ? 1 : 0;
  return IsLinkLocal(address) ? 2 : 3;
}

}  // namespace

// Platform files (sync_net_windows.cpp, sync_net_posix.cpp): inet_pton and
// zone-name resolution.
bool PtonV4(const std::string& text, std::uint8_t* out4);
bool PtonV6(const std::string& text, std::uint8_t* out16);
std::uint32_t ResolveZone(const std::string& zone);

bool IpAddress::SameAddress(const IpAddress& other) const {
  if (v6 != other.v6) return false;
  return std::equal(bytes.begin(), bytes.begin() + (v6 ? 16 : 4), other.bytes.begin());
}

std::optional<IpAddress> ParseIp(const std::string& input) {
  std::string text = input;
  if (text.size() >= 2 && text.front() == '[' && text.back() == ']') text = text.substr(1, text.size() - 2);
  IpAddress address;
  if (text.find(':') == std::string::npos) {
    if (!PtonV4(text, address.bytes.data())) return std::nullopt;
    return address;
  }
  std::string zone;
  if (const auto percent = text.find('%'); percent != std::string::npos) {
    zone = text.substr(percent + 1);
    text = text.substr(0, percent);
    if (zone.empty()) return std::nullopt;
  }
  std::array<std::uint8_t, 16> v6{};
  if (!PtonV6(text, v6.data())) return std::nullopt;
  if (IsV4Mapped(v6)) {
    std::copy(v6.begin() + 12, v6.end(), address.bytes.begin());
    return address;
  }
  address.v6 = true;
  address.bytes = v6;
  if (!zone.empty()) {
    address.scope = ResolveZone(zone);
    if (address.scope == 0) return std::nullopt;
  }
  return address;
}

std::string FormatIp(const IpAddress& address) {
  char buffer[64];
  if (!address.v6) {
    std::snprintf(buffer, sizeof(buffer), "%u.%u.%u.%u", address.bytes[0], address.bytes[1], address.bytes[2],
                  address.bytes[3]);
    return buffer;
  }
  std::string out;
  for (int i = 0; i < 8; ++i) {
    std::snprintf(buffer, sizeof(buffer), "%x", (address.bytes[2 * i] << 8) | address.bytes[2 * i + 1]);
    if (i) out += ':';
    out += buffer;
  }
  if (address.scope != 0) out += "%" + std::to_string(address.scope);
  return out;
}

bool IsLoopback(const IpAddress& address) {
  if (!address.v6) return address.bytes[0] == 127;
  for (int i = 0; i < 15; ++i) if (address.bytes[i] != 0) return false;
  return address.bytes[15] == 1;
}

bool IsLinkLocal(const IpAddress& address) {
  if (!address.v6) return address.bytes[0] == 169 && address.bytes[1] == 254;
  return address.bytes[0] == 0xfe && (address.bytes[1] & 0xc0) == 0x80;
}

bool InSubnet(const IpAddress& address, const InterfaceAddress& network) {
  if (address.v6 != network.address.v6) return false;
  const int width = address.v6 ? 128 : 32;
  const int prefix = std::clamp(network.prefix, 0, width);
  if (prefix == 0) return false;  // a default route is not a directly connected subnet
  for (int bit = 0; bit < prefix; ++bit) {
    const int byte = bit / 8, shift = 7 - bit % 8;
    if (((address.bytes[byte] >> shift) & 1) != ((network.address.bytes[byte] >> shift) & 1)) return false;
  }
  return true;
}

bool PeerAllowed(const IpAddress& peer, const std::optional<IpAddress>& local,
                 const std::vector<InterfaceAddress>& interfaces) {
  if (IsLoopback(peer)) return true;
  // The connection must arrive on an address of an eligible interface, so a
  // VPN or tunnel address never admits anyone.
  if (!local) return false;
  const bool arrived_on_eligible = std::any_of(interfaces.begin(), interfaces.end(), [&](const auto& item) {
    return item.eligible && item.address.SameAddress(*local);
  });
  if (!arrived_on_eligible) return false;
  if (IsLinkLocal(peer)) return true;
  return std::any_of(interfaces.begin(), interfaces.end(),
                     [&](const auto& item) { return item.eligible && InSubnet(peer, item); });
}

bool TargetAllowed(const IpAddress& target, const std::vector<InterfaceAddress>& interfaces) {
  if (IsLoopback(target)) return true;
  if (target.v6 && IsLinkLocal(target)) {
    // An IPv6 link-local address is only routable with the zone of an eligible interface.
    return target.scope != 0 && std::any_of(interfaces.begin(), interfaces.end(), [&](const auto& item) {
             return item.eligible && item.index == target.scope;
           });
  }
  return std::any_of(interfaces.begin(), interfaces.end(),
                     [&](const auto& item) { return item.eligible && InSubnet(target, item); });
}

std::vector<IpAddress> OrderTargets(const std::vector<std::string>& addresses,
                                    const std::vector<InterfaceAddress>& interfaces) {
  std::vector<IpAddress> out;
  for (const auto& text : addresses) {
    const auto parsed = ParseIp(text);
    if (!parsed || !TargetAllowed(*parsed, interfaces)) continue;
    const bool duplicate = std::any_of(out.begin(), out.end(), [&](const IpAddress& existing) {
      return existing.SameAddress(*parsed) && existing.scope == parsed->scope;
    });
    if (!duplicate) out.push_back(*parsed);
  }
  std::stable_sort(out.begin(), out.end(), [](const IpAddress& a, const IpAddress& b) { return Rank(a) < Rank(b); });
  return out;
}

}  // namespace kelpie::desktop_sync
