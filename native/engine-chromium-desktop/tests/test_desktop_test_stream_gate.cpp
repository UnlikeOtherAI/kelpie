#include "../src/desktop_test_stream_gate.h"
#include "../src/desktop_test_stream_collector.h"
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
    using Collector = kelpie::DesktopTestStreamCollector;
    std::vector<Collector::Done> acks;
    std::vector<Collector::Decoded> decodes;
    int stops = 0;
    auto collector = std::make_shared<Collector>(7, 12, 1000,
        [&](int, Collector::Done done) { acks.push_back(std::move(done)); },
        [&](std::string, Collector::Decoded done) { decodes.push_back(std::move(done)); },
        [&] { ++stops; });
    collector->Frame(7, 12, 1, 1001, 10, "first", true);
    collector->Frame(7, 12, 2, 1002, 11, "second", true);
    assert(acks.size() == 2 && decodes.size() == 1 && collector->dropped() == 1);
    acks[0](true); acks[1](true); decodes[0](true, 20, 30);
    const auto sealed = collector->Seal(true, true, true);
    assert(sealed && sealed->size() == 1 && stops == 0);
  }
  {
    using Collector = kelpie::DesktopTestStreamCollector;
    Collector::Done ack;
    Collector::Decoded decode;
    int stops = 0;
    auto collector = std::make_shared<Collector>(7, 12, 1000,
        [&](int, Collector::Done done) { ack = std::move(done); },
        [&](std::string, Collector::Decoded done) { decode = std::move(done); },
        [&] { ++stops; });
    collector->Frame(7, 12, 1, 1001, 10, "first", true);
    collector->Invalidate(); // revoke/navigate/detach before ACK and decode return
    ack(true); decode(true, 20, 30);
    assert(!collector->Seal(true, true, true) && stops == 1);
  }
  {
    using Collector = kelpie::DesktopTestStreamCollector;
    int decodes = 0, stops = 0;
    auto collector = std::make_shared<Collector>(7, 12, 1000,
        [](int, Collector::Done done) { done(false); },
        [&](std::string, Collector::Decoded) { ++decodes; },
        [&] { ++stops; });
    collector->Frame(7, 12, 1, 1001, 10, "first", true);
    assert(decodes == 0 && stops == 1 && !collector->Seal(true, true, true));
  }
  {
    using Collector = kelpie::DesktopTestStreamCollector;
    Collector::Done ack;
    int stops = 0;
    auto collector = std::make_shared<Collector>(7, 12, 1000,
        [&](int, Collector::Done done) { ack = std::move(done); },
        [](std::string, Collector::Decoded done) { done(true, 20, 30); },
        [&] { ++stops; });
    collector->Frame(7, 12, 1, 1001, 10, "first", true);
    ack(true); ack(true); // duplicate ACK completion invalidates the seal
    assert(!collector->Seal(true, true, true) && stops == 1);
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
