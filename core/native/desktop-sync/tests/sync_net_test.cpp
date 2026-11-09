// The address rule, address parsing and the 64-entry replay window.
#include <cassert>
#include <cstdio>

#include "sync_channel.h"
#include "sync_net.h"

using namespace kelpie::desktop_sync;

namespace {

IpAddress Ip(const std::string& text) {
  const auto parsed = ParseIp(text);
  assert(parsed);
  return *parsed;
}

InterfaceAddress Net(const std::string& address, int prefix, bool eligible, std::uint32_t index) {
  return {Ip(address), prefix, index, eligible};
}

void Parsing() {
  assert(!Ip("192.168.1.20").v6);
  assert(FormatIp(Ip("192.168.1.20")) == "192.168.1.20");
  const auto mapped = Ip("::ffff:192.168.1.20");
  assert(!mapped.v6 && mapped.SameAddress(Ip("192.168.1.20")));
  assert(Ip("[fe80::1%7]").scope == 7 && Ip("fe80::1%7").v6);
  assert(FormatIp(Ip("fe80::1%7")) == "fe80:0:0:0:0:0:0:1%7");
  assert(Ip("FE80::1").SameAddress(Ip("fe80::1")));
  for (const char* bad : {"", "1.2.3", "256.1.1.1", "1.2.3.4.5", "example.com", "fe80::1%", "::g", "1.2.3.4%1"}) {
    assert(!ParseIp(bad));
  }
  assert(IsLoopback(Ip("127.8.9.10")) && IsLoopback(Ip("::1")) && !IsLoopback(Ip("10.0.0.1")));
  assert(IsLinkLocal(Ip("169.254.10.1")) && IsLinkLocal(Ip("fe80::abcd")) && IsLinkLocal(Ip("febf::1")));
  assert(!IsLinkLocal(Ip("fec0::1")) && !IsLinkLocal(Ip("192.168.1.1")));
}

void Rule() {
  const std::vector<InterfaceAddress> interfaces = {
      Net("192.168.1.20", 24, true, 4),      // Wi-Fi
      Net("fe80::20", 64, true, 4),
      Net("2001:db8:1::20", 64, true, 4),
      Net("10.8.0.2", 24, false, 9),         // VPN tunnel
      Net("172.30.44.1", 24, false, 12),     // virtual switch
      Net("127.0.0.1", 8, false, 1),
  };
  // Loopback always; the directly connected subnet of an eligible interface.
  assert(PeerAllowed(Ip("127.0.0.1"), std::nullopt, interfaces));
  assert(PeerAllowed(Ip("::1"), Ip("::1"), interfaces));
  assert(PeerAllowed(Ip("192.168.1.77"), Ip("192.168.1.20"), interfaces));
  assert(PeerAllowed(Ip("::ffff:192.168.1.77"), Ip("::ffff:192.168.1.20"), interfaces));
  assert(PeerAllowed(Ip("2001:db8:1::99"), Ip("2001:db8:1::20"), interfaces));
  assert(PeerAllowed(Ip("fe80::99%4"), Ip("fe80::20%4"), interfaces));
  assert(PeerAllowed(Ip("169.254.3.3"), Ip("192.168.1.20"), interfaces));
  // Outside the subnet, routed, or arriving on a VPN or virtual interface.
  assert(!PeerAllowed(Ip("192.168.2.77"), Ip("192.168.1.20"), interfaces));
  assert(!PeerAllowed(Ip("8.8.8.8"), Ip("192.168.1.20"), interfaces));
  assert(!PeerAllowed(Ip("10.8.0.5"), Ip("10.8.0.2"), interfaces));
  assert(!PeerAllowed(Ip("172.30.44.10"), Ip("172.30.44.1"), interfaces));
  assert(!PeerAllowed(Ip("192.168.1.77"), Ip("10.8.0.2"), interfaces));
  assert(!PeerAllowed(Ip("192.168.1.77"), std::nullopt, interfaces));
  // A /0 "subnet" is a default route, never a directly connected network.
  assert(!PeerAllowed(Ip("8.8.8.8"), Ip("192.168.1.20"), {Net("192.168.1.20", 0, true, 4)}));

  // Outgoing applies the same rule; IPv6 link-local needs an eligible zone.
  assert(TargetAllowed(Ip("192.168.1.30"), interfaces));
  assert(!TargetAllowed(Ip("10.8.0.9"), interfaces));
  assert(TargetAllowed(Ip("fe80::30%4"), interfaces));
  assert(!TargetAllowed(Ip("fe80::30%9"), interfaces));
  assert(!TargetAllowed(Ip("fe80::30"), interfaces));
  assert(TargetAllowed(Ip("127.0.0.1"), interfaces));
  const auto ordered = OrderTargets({"2001:db8:1::30", "fe80::30%4", "10.8.0.9", "bogus", "127.0.0.1",
                                     "192.168.1.30", "192.168.1.30"}, interfaces);
  assert(ordered.size() == 4);
  assert(FormatIp(ordered[0]) == "192.168.1.30");
  assert(IsLinkLocal(ordered[1]) && ordered[1].v6);
  assert(ordered[2].v6 && !IsLinkLocal(ordered[2]));
  assert(IsLoopback(ordered[3]));

  // The real enumeration runs and never marks loopback eligible.
  for (const auto& entry : EnumerateInterfaces()) assert(!(entry.eligible && IsLoopback(entry.address)));
}

void Window() {
  ReplayWindow window;
  assert(!window.Acceptable(0));
  assert(window.Acceptable(5));
  window.Accept(5);
  assert(!window.Acceptable(5));               // a replay
  assert(window.Acceptable(3));                // out of order, unseen
  window.Accept(3);
  assert(!window.Acceptable(3));
  window.Accept(70);
  assert(!window.Acceptable(5));               // 65 below the highest
  assert(window.Acceptable(6));                // exactly 64 below, unseen
  window.Accept(6);
  assert(!window.Acceptable(6) && !window.Acceptable(70));
  assert(window.Acceptable(69) && window.Acceptable(71));
  window.Accept(1000);                         // a jump past the window clears it
  assert(!window.Acceptable(70) && window.Acceptable(999) && !window.Acceptable(1000));
  window.Accept(1064);                         // exactly one window ahead keeps 1000 as seen
  assert(!window.Acceptable(1000) && window.Acceptable(1001));
}

}  // namespace

int main() {
  Parsing();
  Rule();
  Window();
  std::puts("sync_net_test passed");
  return 0;
}
