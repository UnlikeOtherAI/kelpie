#pragma once

#include <cmath>
#include <cstddef>
#include <cstdint>
#include <mutex>
#include <optional>
#include <vector>

// Test-only numeric admission for one owned CEF browser and one workflow epoch.
// No pixels, page text, URL, or authentication material are retained here.
class CEFHostedStreamFence {
public:
    enum class Decision { reject, ackDrop, ackDecode, ackStop };
    // Fixed diagnostics only: stop cause is separate from the first invalidation cause.
    enum class Cause { none, cap, identity, receipt, protocol, size, decodeIdentity, decodeOutput,
                       external, sealPending, sealIdentity };
    struct Sample {
        double receiptMs;
        double protocolMs;
        int x;
        int y;
    };

    CEFHostedStreamFence(int browserID, uint64_t epoch, double startMs, bool overlay = false)
        : browserID_(browserID), epoch_(epoch), startMs_(startMs),
          maximumFrames_(overlay ? 256 : 64), maximumDurationMs_(overlay ? 10000 : 4000) {}

    Decision admit(int browserID, uint64_t epoch, int sessionID, double receiptMs,
                   double protocolMs, size_t encodedBytes, bool identityCurrent, uint64_t *decodeToken = nullptr) {
        std::lock_guard<std::mutex> guard(lock_);
        if (!active_ || browserID != browserID_ || epoch != epoch_ || sessionID <= 0) { return Decision::reject; }
        if (stopRequested_) { return Decision::ackDrop; }
        Cause failure = Cause::none;
        if (!identityCurrent) { failure = Cause::identity; }
        else if (!std::isfinite(receiptMs) || receiptMs < startMs_ || receiptMs < lastReceiptMs_) {
            failure = Cause::receipt;
        } else if (!std::isfinite(protocolMs)) { failure = Cause::protocol; }
        else if (encodedBytes == 0 || encodedBytes > maximumFrameBytes_) { failure = Cause::size; }
        if (failure != Cause::none) {
            invalidateLocked(failure);
            stopRequested_ = true;
            stopCause_ = failure;
            return Decision::ackStop;
        }
        lastReceiptMs_ = receiptMs;
        if (receiptMs - startMs_ > maximumDurationMs_ || observed_ >= maximumFrames_ ||
            encodedBytes > maximumTotalBytes_ - totalBytes_) {
            stopRequested_ = true;
            stopCause_ = Cause::cap;
            return Decision::ackStop;
        }
        ++observed_;
        totalBytes_ += encodedBytes;
        // CDP can deliver an older encoded frame after a newer one. ACK and count it,
        // but never decode it or move the protocol high-water mark backwards.
        if (protocolMs < lastProtocolMs_) { ++stale_; return Decision::ackDrop; }
        lastProtocolMs_ = protocolMs;
        if (decodePending_) { ++dropped_; return Decision::ackDrop; }
        decodePending_ = true;
        pendingDecodeToken_ = ++nextDecodeToken_;
        if (decodeToken != nullptr) { *decodeToken = pendingDecodeToken_; }
        pendingReceiptMs_ = receiptMs;
        pendingProtocolMs_ = protocolMs;
        return Decision::ackDecode;
    }

    void complete(uint64_t epoch, uint64_t decodeToken, bool identityCurrent, bool decoded, int x, int y) {
        std::lock_guard<std::mutex> guard(lock_);
        if (epoch != epoch_ || !decodePending_ || decodeToken != pendingDecodeToken_) { return; }
        decodePending_ = false;
        if (!active_ || !identityCurrent || !decoded || x < 0 || y < 0 || x > 1920 || y > 1920) {
            invalidateLocked(!identityCurrent ? Cause::decodeIdentity : Cause::decodeOutput);
            return;
        }
        samples_.push_back({pendingReceiptMs_, pendingProtocolMs_, x, y});
    }

    void invalidate() {
        std::lock_guard<std::mutex> guard(lock_);
        invalidateLocked(Cause::external);
        active_ = false;
    }

    // Called only after Page.stopScreencast has retired and the final identity/grant audit succeeds.
    std::optional<std::vector<Sample>> seal(bool identityCurrent) {
        std::lock_guard<std::mutex> guard(lock_);
        if (!active_) { return std::nullopt; }
        active_ = false;
        if (!identityCurrent) { invalidateLocked(Cause::sealIdentity); }
        if (decodePending_) { invalidateLocked(Cause::sealPending); }
        if (!valid_) { samples_.clear(); return std::nullopt; }
        return samples_;
    }

    Cause stopCause() const { std::lock_guard<std::mutex> guard(lock_); return stopCause_; }
    Cause failureCause() const { std::lock_guard<std::mutex> guard(lock_); return failureCause_; }

    size_t stale() const {
        std::lock_guard<std::mutex> guard(lock_);
        return stale_;
    }

    size_t dropped() const {
        std::lock_guard<std::mutex> guard(lock_);
        return dropped_;
    }

private:
    void invalidateLocked(Cause cause) {
        valid_ = false;
        if (failureCause_ == Cause::none) { failureCause_ = cause; }
    }
    static constexpr size_t maximumFrameBytes_ = 2 * 1024 * 1024;
    static constexpr size_t maximumTotalBytes_ = 32 * 1024 * 1024;
    mutable std::mutex lock_;
    const int browserID_;
    const uint64_t epoch_;
    const double startMs_;
    const size_t maximumFrames_;
    const double maximumDurationMs_;
    Cause stopCause_ = Cause::none;
    Cause failureCause_ = Cause::none;
    bool active_ = true;
    bool valid_ = true;
    bool decodePending_ = false;
    bool stopRequested_ = false;
    uint64_t pendingDecodeToken_ = 0;
    uint64_t nextDecodeToken_ = 0;
    size_t observed_ = 0;
    size_t totalBytes_ = 0;
    size_t dropped_ = 0;
    size_t stale_ = 0;
    double lastReceiptMs_ = 0;
    double lastProtocolMs_ = 0;
    double pendingReceiptMs_ = 0;
    double pendingProtocolMs_ = 0;
    std::vector<Sample> samples_;
};
