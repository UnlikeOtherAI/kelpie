#pragma once
#include "desktop_test_stream_gate.h"

#include <atomic>
#include <functional>
#include <memory>
#include <string>
#include <utility>

namespace kelpie {
// Test-only transport-independent coordinator. The caller must provide the
// exact fixture/browser/lease checks and join observer ingress before sealing.
class DesktopTestStreamCollector : public std::enable_shared_from_this<DesktopTestStreamCollector> {
 public:
  using Done = std::function<void(bool)>;
  using Decoded = std::function<void(bool, int, int)>;
  using SendAck = std::function<void(int, Done)>;
  using Decode = std::function<void(std::string, Decoded)>;
  using Stop = std::function<void()>; // Must only schedule work; never block the CEF callback.

  DesktopTestStreamCollector(int browser, std::uint64_t epoch, double start_ms,
                             SendAck ack, Decode decode, Stop stop)
      : epoch_(epoch), gate_(browser, epoch, start_ms), ack_(std::move(ack)),
        decode_(std::move(decode)), stop_(std::move(stop)) {}

  void Frame(int browser, std::uint64_t epoch, int session, double receipt_ms,
             double protocol_ms, std::string encoded, bool identity_current) {
    const auto decision = gate_.Admit(browser, epoch, session, receipt_ms, protocol_ms,
                                      encoded.size(), identity_current && current_.load());
    if (decision.decision == DesktopTestStreamGate::Decision::kReject) { Invalidate(); return; }
    const std::weak_ptr<DesktopTestStreamCollector> weak = weak_from_this();
    try {
      ack_(session, [weak, token=decision.ack](bool success) {
        if (auto self=weak.lock()) if (!self->gate_.Ack(token, success)) self->Invalidate();
      });
    } catch (...) { gate_.Ack(decision.ack, false); Invalidate(); return; }
    if (decision.decision == DesktopTestStreamGate::Decision::kAckStop) { RequestStop(); return; }
    if (decision.decision != DesktopTestStreamGate::Decision::kAckDecode) return;
    // A synchronous ACK failure may have invalidated the reservation already.
    if (!current_.load()) {
      gate_.Decoded(epoch, decision.decode, false, false, 0, 0);
      return;
    }
    try {
      decode_(std::move(encoded), [weak, epoch, token=decision.decode](bool success, int x, int y) {
        if (auto self=weak.lock()) {
          if (!self->gate_.Decoded(epoch, token, self->current_.load(), success, x, y)) self->Invalidate();
        }
      });
    } catch (...) { gate_.Decoded(epoch, decision.decode, false, false, 0, 0); Invalidate(); }
  }

  void Invalidate() { current_.store(false); gate_.Invalidate(); RequestStop(); }
  std::optional<std::vector<DesktopTestStreamGate::Sample>> Seal(bool ingress_drained,
                                                                bool stop_succeeded,
                                                                bool final_authority_document_viewport) {
    if (!ingress_drained || !current_.load()) { gate_.Invalidate(); return std::nullopt; }
    return gate_.Seal(stop_succeeded, final_authority_document_viewport);
  }
  std::size_t observed() const { return gate_.observed(); }
  std::size_t dropped() const { return gate_.dropped(); }

 private:
  void RequestStop() {
    if (!stop_requested_.exchange(true)) { try { if (stop_) stop_(); } catch (...) { gate_.Invalidate(); } }
  }
  const std::uint64_t epoch_;
  DesktopTestStreamGate gate_;
  SendAck ack_;
  Decode decode_;
  Stop stop_;
  std::atomic<bool> current_{true}, stop_requested_{false};
};
}  // namespace kelpie
