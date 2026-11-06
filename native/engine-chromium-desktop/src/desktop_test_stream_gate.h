#pragma once

#include <cmath>
#include <cstddef>
#include <cstdint>
#include <map>
#include <mutex>
#include <optional>
#include <vector>

namespace kelpie {
// Test-only numeric admission. The caller owns origin, lease, grant, viewport,
// ACK transport and final audit; a page nonce is never treated as authority.
class DesktopTestStreamGate {
 public:
  enum class Decision { kReject, kAckDrop, kAckDecode, kAckStop };
  struct Sample { double receipt_ms, protocol_ms; int x, y; };
  struct Admission { Decision decision = Decision::kReject; std::uint64_t ack = 0, decode = 0; };

  DesktopTestStreamGate(int browser, std::uint64_t epoch, double start_ms)
      : browser_(browser), epoch_(epoch), start_ms_(start_ms), last_receipt_(start_ms) {}

  Admission Admit(int browser, std::uint64_t epoch, int session, double receipt_ms,
                  double protocol_ms, std::size_t encoded_bytes, bool identity_current) {
    std::lock_guard lock(mutex_);
    if (!active_ || browser != browser_ || epoch != epoch_ || session <= 0) {
      InvalidateLocked(); return {};
    }
    if (pending_acks_.size() >= kMaxPendingAcks) { InvalidateLocked(); return {}; }
    const auto ack = ++next_token_;
    pending_acks_.emplace(ack, session);
    if (stop_requested_) return {Decision::kAckDrop, ack, 0};
    if (!identity_current || !std::isfinite(start_ms_) || start_ms_ < 0 ||
        !std::isfinite(receipt_ms) || receipt_ms < last_receipt_ ||
        !std::isfinite(protocol_ms) || protocol_ms < 0 || protocol_ms < last_protocol_ ||
        encoded_bytes == 0 || encoded_bytes > kMaxFrameBytes) {
      InvalidateLocked(); stop_requested_ = true; return {Decision::kAckStop, ack, 0};
    }
    last_receipt_ = receipt_ms;
    last_protocol_ = protocol_ms;
    if (receipt_ms - start_ms_ > kMaxDurationMs || observed_ >= kMaxEvents ||
        encoded_bytes > kMaxTotalBytes - total_bytes_) {
      stop_requested_ = true; return {Decision::kAckStop, ack, 0};
    }
    ++observed_; total_bytes_ += encoded_bytes;
    if (pending_decode_) { ++dropped_; return {Decision::kAckDrop, ack, 0}; }
    pending_decode_ = ++next_token_;
    decode_receipt_ = receipt_ms; decode_protocol_ = protocol_ms;
    return {Decision::kAckDecode, ack, pending_decode_};
  }

  bool Ack(std::uint64_t token, bool success) {
    std::lock_guard lock(mutex_);
    if (pending_acks_.erase(token) != 1 || !success) { InvalidateLocked(); return false; }
    return true;
  }
  bool Decoded(std::uint64_t epoch, std::uint64_t token, bool identity_current,
               bool success, int x, int y) {
    std::lock_guard lock(mutex_);
    if (!pending_decode_ || epoch != epoch_ || token != pending_decode_) { InvalidateLocked(); return false; }
    pending_decode_ = 0;
    if (!active_ || !valid_ || !identity_current || !success || x < 0 || y < 0 || x > 1920 || y > 1920) {
      InvalidateLocked(); return false;
    }
    samples_.push_back({decode_receipt_, decode_protocol_, x, y});
    return true;
  }
  void Invalidate() { std::lock_guard lock(mutex_); InvalidateLocked(); }
  std::optional<std::vector<Sample>> Seal(bool stop_succeeded, bool final_identity_current) {
    std::lock_guard lock(mutex_);
    if (!active_ || !valid_ || !stop_succeeded || !final_identity_current ||
        pending_decode_ || !pending_acks_.empty()) { InvalidateLocked(); return std::nullopt; }
    active_ = false; return samples_;
  }
  std::size_t observed() const { std::lock_guard lock(mutex_); return observed_; }
  std::size_t dropped() const { std::lock_guard lock(mutex_); return dropped_; }

 private:
  void InvalidateLocked() { valid_ = false; stop_requested_ = true; samples_.clear(); }
  static constexpr std::size_t kMaxEvents = 256, kMaxPendingAcks = 3;
  static constexpr std::size_t kMaxFrameBytes = 2 * 1024 * 1024, kMaxTotalBytes = 32 * 1024 * 1024;
  static constexpr double kMaxDurationMs = 10000;
  int browser_;
  std::uint64_t epoch_, next_token_ = 0, pending_decode_ = 0;
  double start_ms_, last_receipt_, last_protocol_ = 0, decode_receipt_ = 0, decode_protocol_ = 0;
  std::size_t observed_ = 0, dropped_ = 0, total_bytes_ = 0;
  bool active_ = true, valid_ = true, stop_requested_ = false;
  mutable std::mutex mutex_;
  std::map<std::uint64_t, int> pending_acks_;
  std::vector<Sample> samples_;
};
}  // namespace kelpie
