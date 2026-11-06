#include "../../apps/macos/Kelpie/Renderer/CEFHostedStreamFence.h"
#include <cassert>
#include <limits>

int main() {
    using Fence = CEFHostedStreamFence;
    Fence a(10, 20, 100);
    uint64_t token = 0;
    assert(a.admit(11, 20, 1, 101, 1, 100, true) == Fence::Decision::reject);
    assert(a.admit(10, 21, 1, 101, 1, 100, true) == Fence::Decision::reject);
    assert(a.admit(10, 20, 1, 101, 1, 100, true, &token) == Fence::Decision::ackDecode);
    assert(a.admit(10, 20, 2, 102, 2, 100, true) == Fence::Decision::ackDrop);
    a.complete(20, token, true, true, 30, 40);
    assert(a.dropped() == 1);
    a.complete(20, 999, true, true, 0, 0);
    auto samples = a.seal(true);
    assert(samples && samples->size() == 1 && samples->front().x == 30);
    assert(!a.seal(true));
    assert(a.admit(10, 20, 3, 103, 3, 100, true) == Fence::Decision::reject);

    Fence stale(10, 22, 100);
    assert(stale.admit(10, 22, 1, 101, 1, 100, true, &token) == Fence::Decision::ackDecode);
    stale.complete(22, token, false, true, 1, 1);
    assert(!stale.seal(true));
    assert(stale.failureCause() == Fence::Cause::decodeIdentity);

    Fence pending(10, 23, 100);
    assert(pending.admit(10, 23, 1, 101, 1, 100, true, &token) == Fence::Decision::ackDecode);
    assert(!pending.seal(true));
    assert(pending.failureCause() == Fence::Cause::sealPending);
    pending.complete(23, token, true, true, 1, 1);
    assert(!pending.seal(true));

    Fence invalid(10, 24, 100);
    assert(invalid.admit(10, 24, 1, 101, std::numeric_limits<double>::quiet_NaN(), 100, true) == Fence::Decision::ackStop);
    assert(!invalid.seal(true));
    assert(invalid.stopCause() == Fence::Cause::protocol && invalid.failureCause() == Fence::Cause::protocol);

    Fence regress(10, 27, 100);
    assert(regress.admit(10, 27, 1, 101, 10, 100, true, &token) == Fence::Decision::ackDecode);
    regress.complete(27, token, true, true, 1, 1);
    assert(regress.admit(10, 27, 1, 102, 9, 100, true) == Fence::Decision::ackDrop);
    assert(regress.admit(10, 27, 1, 103, 9.5, 100, true) == Fence::Decision::ackDrop);
    assert(regress.stale() == 2);
    assert(regress.admit(10, 27, 1, 104, 11, 100, true, &token) == Fence::Decision::ackDecode);
    regress.complete(27, token, true, true, 2, 2);
    assert(regress.seal(true)->size() == 2);

    Fence badIdentity(10, 28, 100);
    assert(badIdentity.admit(10, 28, 1, 101, 10, 100, true, &token) == Fence::Decision::ackDecode);
    badIdentity.complete(28, token, true, true, 1, 1);
    assert(badIdentity.admit(10, 28, 1, 102, 9, 100, false) == Fence::Decision::ackStop);
    assert(badIdentity.stale() == 0 && badIdentity.failureCause() == Fence::Cause::identity);
    assert(!badIdentity.seal(true));

    Fence staleCount(10, 29, 100);
    assert(staleCount.admit(10, 29, 1, 101, 10, 100, true, &token) == Fence::Decision::ackDecode);
    staleCount.complete(29, token, true, true, 1, 1);
    for (int i = 0; i < 63; ++i)
        assert(staleCount.admit(10, 29, 1, 102 + i, 9, 100, true) == Fence::Decision::ackDrop);
    assert(staleCount.admit(10, 29, 1, 165, 9, 100, true) == Fence::Decision::ackStop);
    assert(staleCount.stale() == 63 && staleCount.stopCause() == Fence::Cause::cap);

    Fence repeatedSession(10, 26, 100);
    uint64_t first = 0, second = 0;
    assert(repeatedSession.admit(10, 26, 7, 101, 1, 100, true, &first) == Fence::Decision::ackDecode);
    repeatedSession.complete(26, first, true, true, 10, 10);
    assert(repeatedSession.admit(10, 26, 7, 102, 2, 100, true, &second) == Fence::Decision::ackDecode);
    assert(first != second);
    repeatedSession.complete(26, first, true, true, 99, 99); // Late callback for same CDP session.
    repeatedSession.complete(26, second, true, true, 20, 20);
    auto ordered = repeatedSession.seal(true);
    assert(ordered && ordered->size() == 2 && ordered->back().x == 20);

    Fence bounded(10, 25, 100);
    for (int i = 0; i < 64; ++i) {
        assert(bounded.admit(10, 25, 1, 101 + i, 1 + i, 100, true, &token) == Fence::Decision::ackDecode);
        bounded.complete(25, token, true, true, i, i);
    }
    assert(bounded.admit(10, 25, 65, 200, 100, 100, true) == Fence::Decision::ackStop);
    assert(bounded.admit(10, 25, 66, 201, 101, 100, true) == Fence::Decision::ackDrop);
    assert(bounded.stopCause() == Fence::Cause::cap && bounded.failureCause() == Fence::Cause::none);
    assert(bounded.seal(true)->size() == 64);
    assert(!bounded.seal(true));

    Fence overlay(10, 30, 100, true);
    for (int i = 0; i < 256; ++i) {
        assert(overlay.admit(10, 30, 1, 101 + i * 25, 1 + i, 100, true, &token) == Fence::Decision::ackDecode);
        overlay.complete(30, token, true, true, i, i);
    }
    assert(overlay.admit(10, 30, 1, 6502, 257, 100, true) == Fence::Decision::ackStop);
    assert(overlay.stopCause() == Fence::Cause::cap && overlay.seal(true)->size() == 256);
    Fence overlayDuration(10, 31, 100, true);
    assert(overlayDuration.admit(10, 31, 1, 10101, 1, 100, true) == Fence::Decision::ackStop);
    assert(overlayDuration.stopCause() == Fence::Cause::cap);
}
