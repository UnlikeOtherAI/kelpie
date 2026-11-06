#include "../src/desktop_test_stream_gate.h"
#include <cassert>
#include <limits>

using Gate = kelpie::DesktopTestStreamGate;
int main() {
  {
    Gate gate(7, 12, 1000);
    const auto first = gate.Admit(7, 12, 1, 1001, 10, 128, true);
    assert(first.decision == Gate::Decision::kAckDecode);
    const auto busy = gate.Admit(7, 12, 2, 1002, 11, 128, true);
    assert(busy.decision == Gate::Decision::kAckDrop);
    gate.Ack(first.ack, true); gate.Ack(busy.ack, true);
    gate.Decoded(12, first.decode, true, true, 20, 30);
    const auto sealed = gate.Seal(true, true);
    assert(sealed && sealed->size() == 1 && gate.observed() == 2 && gate.dropped() == 1);
  }
  {
    Gate gate(7, 12, 1000);
    const auto frame = gate.Admit(7, 12, 1, 1001, 10, 128, true);
    gate.Ack(frame.ack, true); gate.Decoded(12, frame.decode, true, true, 20, 30);
    gate.Invalidate(); // navigation, detach, authorization or geometry loss
    assert(!gate.Seal(true, true));
  }
  {
    Gate gate(7, 12, 1000);
    const auto frame = gate.Admit(7, 12, 1, 1001, 10, 128, true);
    gate.Ack(frame.ack, false); gate.Decoded(12, frame.decode, true, true, 20, 30);
    assert(!gate.Seal(true, true));
  }
  {
    Gate gate(7, 12, 1000);
    const auto frame = gate.Admit(7, 12, 1, 1001, std::numeric_limits<double>::quiet_NaN(), 128, true);
    assert(frame.decision == Gate::Decision::kAckStop);
    gate.Ack(frame.ack, true); assert(!gate.Seal(true, true));
  }
  {
    Gate gate(7, 12, 1000);
    const auto frame = gate.Admit(7, 12, 1, 1001, 10, 128, true);
    gate.Decoded(12, frame.decode, true, true, 20, 30);
    assert(!gate.Seal(true, true)); // unacknowledged event
  }
  {
    Gate gate(7, 12, 1000);
    const auto frame = gate.Admit(7, 12, 1, 1001, 10, 128, true);
    gate.Ack(frame.ack, true); gate.Decoded(12, frame.decode, true, true, 20, 30);
    assert(!gate.Seal(true, false)); // final identity or grant audit failed
  }
  {
    Gate gate(7, 12, 1000);
    const auto frame = gate.Admit(7, 12, 1, 1001, 10, 2 * 1024 * 1024 + 1, true);
    assert(frame.decision == Gate::Decision::kAckStop);
    gate.Ack(frame.ack, true); assert(!gate.Seal(true, true));
  }
  {
    Gate gate(7, 12, 1000);
    for (int index = 0; index < 256; ++index) {
      const auto frame = gate.Admit(7, 12, index + 1, 1001 + index, index + 1, 128, true);
      assert(frame.decision == Gate::Decision::kAckDecode);
      gate.Ack(frame.ack, true); gate.Decoded(12, frame.decode, true, true, 20, 30);
    }
    const auto limit = gate.Admit(7, 12, 257, 1257, 257, 128, true);
    assert(limit.decision == Gate::Decision::kAckStop);
    gate.Ack(limit.ack, true);
    const auto sealed = gate.Seal(true, true);
    assert(sealed && sealed->size() == 256);
  }
  {
    Gate gate(7, 12, 1000);
    const auto a = gate.Admit(7, 12, 1, 1001, 10, 128, true);
    const auto b = gate.Admit(7, 12, 2, 1002, 11, 128, true);
    const auto c = gate.Admit(7, 12, 3, 1003, 12, 128, true);
    const auto overflow = gate.Admit(7, 12, 4, 1004, 13, 128, true);
    assert(overflow.decision == Gate::Decision::kReject);
    gate.Ack(a.ack, true); gate.Ack(b.ack, true); gate.Ack(c.ack, true);
    gate.Decoded(12, a.decode, true, true, 20, 30);
    assert(!gate.Seal(true, true));
  }
  return 0;
}
