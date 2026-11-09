// Overflow-safe clock arithmetic for values a peer controls.
#include <cassert>
#include <cstdint>
#include <cstdio>
#include <limits>

#include "sync_protocol.h"

using namespace kelpie::desktop_sync;

int main() {
  constexpr std::int64_t kMin = std::numeric_limits<std::int64_t>::min();
  constexpr std::int64_t kMax = std::numeric_limits<std::int64_t>::max();
  const std::int64_t now = 1794250000000;
  assert(WithinClockSkew(now, now));
  assert(WithinClockSkew(now + kMaxSkewMillis, now) && WithinClockSkew(now - kMaxSkewMillis, now));
  assert(!WithinClockSkew(now + kMaxSkewMillis + 1, now) && !WithinClockSkew(now - kMaxSkewMillis - 1, now));
  // The full int64 range on either side never overflows.
  assert(!WithinClockSkew(kMin, kMax) && !WithinClockSkew(kMax, kMin));
  for (const std::int64_t local : {std::int64_t{-1}, std::int64_t{0}, now}) {
    assert(!WithinClockSkew(kMin, local) && !WithinClockSkew(kMax, local));
    assert(!WithinClockSkew(local, kMin) && !WithinClockSkew(local, kMax));
    assert(WithinClockSkew(local, local));
  }
  assert(WithinClockSkew(kMin + 5, kMin) && WithinClockSkew(kMax - 5, kMax));

  assert(MillisUntil(now + 1000, now, 600000) == 1000);
  assert(MillisUntil(now - 1000, now, 600000) == 0);
  assert(MillisUntil(kMax, kMin, 600000) == 600000);
  assert(MillisUntil(kMin, kMax, 600000) == 0);
  assert(MillisUntil(kMax, now, 600000) == 600000);
  std::puts("sync_protocol_test passed");
  return 0;
}
