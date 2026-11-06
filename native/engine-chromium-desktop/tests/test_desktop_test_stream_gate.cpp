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
  return 0;
}
