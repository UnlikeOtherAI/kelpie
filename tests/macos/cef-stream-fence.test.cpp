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

    Fence pending(10, 23, 100);
    assert(pending.admit(10, 23, 1, 101, 1, 100, true, &token) == Fence::Decision::ackDecode);
    assert(!pending.seal(true));
    pending.complete(23, token, true, true, 1, 1);
    assert(!pending.seal(true));

    Fence invalid(10, 24, 100);
    assert(invalid.admit(10, 24, 1, 101, std::numeric_limits<double>::quiet_NaN(), 100, true) == Fence::Decision::ackStop);
    assert(!invalid.seal(true));

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
    assert(bounded.seal(true)->size() == 64);
    assert(!bounded.seal(true));
}
