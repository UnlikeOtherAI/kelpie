#pragma once

// The sync address rule. A peer is reachable only over loopback, IPv4/IPv6
// link-local, or the directly connected subnet of an eligible interface:
// physical, up, Wi-Fi or Ethernet. VPN, tunnel, point-to-point and cellular
// interfaces are never eligible. The listener and the client apply the same
// rule.

#include <array>
#include <cstdint>
#include <optional>
#include <string>
#include <vector>

namespace kelpie::desktop_sync {

struct IpAddress {
  bool v6 = false;
  std::array<std::uint8_t, 16> bytes{};  // IPv4 uses the first 4
  std::uint32_t scope = 0;               // IPv6 zone index, 0 when absent

  bool SameAddress(const IpAddress& other) const;  // ignores the zone
};

// Accepts dotted IPv4, IPv6 (optionally bracketed, optional %zone) and
// IPv4-mapped IPv6, which becomes IPv4.
std::optional<IpAddress> ParseIp(const std::string& text);
// Numeric text for a socket API: no brackets, IPv6 zone as a number.
std::string FormatIp(const IpAddress& address);

bool IsLoopback(const IpAddress& address);
bool IsLinkLocal(const IpAddress& address);

struct InterfaceAddress {
  IpAddress address;
  int prefix = 0;  // on-link prefix length
  std::uint32_t index = 0;
  bool eligible = false;
};

// Every unicast address of every interface, each marked eligible or not.
// Platform code: GetAdaptersAddresses on Windows, getifaddrs elsewhere.
std::vector<InterfaceAddress> EnumerateInterfaces();

bool InSubnet(const IpAddress& address, const InterfaceAddress& network);

// Incoming: `local` is the address the connection arrived on.
bool PeerAllowed(const IpAddress& peer, const std::optional<IpAddress>& local,
                 const std::vector<InterfaceAddress>& interfaces);
// Outgoing: the address we are about to connect to.
bool TargetAllowed(const IpAddress& target, const std::vector<InterfaceAddress>& interfaces);

// The advertised addresses that pass TargetAllowed, IPv4 first, then
// link-local, then other IPv6, loopback last. Unparseable entries are dropped.
std::vector<IpAddress> OrderTargets(const std::vector<std::string>& addresses,
                                    const std::vector<InterfaceAddress>& interfaces);

}  // namespace kelpie::desktop_sync
