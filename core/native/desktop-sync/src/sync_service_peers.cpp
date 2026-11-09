// Peer bookkeeping: discovery callbacks, the initiator rule and handshake
// scheduling, backoff, warm-up completion and the status payload.
#include <algorithm>

#include "sync_service.h"

#include "base64url.h"
#include "protocol.h"

namespace kelpie {
namespace {

constexpr std::size_t kHandshakesPerMinute = 10;
constexpr std::size_t kConcurrentHandshakes = 4;

}  // namespace

void DesktopCookieSync::Impl::OnFound(std::uint64_t epoch_id, const SyncPeerAdvert& advert) {
  const auto value = [&](const char* key) {
    const auto it = advert.txt.find(key);
    return it == advert.txt.end() ? std::string() : it->second;
  };
  const std::string replica = value("id");
  const auto decoded = sync::Base64UrlDecode(replica);
  if (value("v") != "1" || !decoded || decoded->size() != 16 || advert.port <= 0 || advert.port > 65535 ||
      advert.addresses.empty()) return;
  std::lock_guard lock(mu_);
  if (!epoch_ || epoch_->id != epoch_id || replica == epoch_->replica) return;
  const auto accepted = sync::AcceptedAccountHints(epoch_->subject, Now());
  if (std::find(accepted.begin(), accepted.end(), value("h")) == accepted.end()) return;  // another account
  Peer& peer = peers_[replica];
  const auto now = Clock::now();
  if (peer.replica.empty()) {
    peer.replica = replica;
    peer.first_seen = now;
    peer.in_warmup_window = !warm_done_ && now - epoch_->opened < config_.timings.warmup_window;
  }
  peer.instance = advert.instance;
  peer.addresses = advert.addresses;
  peer.port = advert.port;
  peer.advertised = true;
  woken_ = true;
  wake_.notify_all();
}

void DesktopCookieSync::Impl::OnLost(std::uint64_t epoch_id, const std::string& instance) {
  std::lock_guard lock(mu_);
  if (!epoch_ || epoch_->id != epoch_id) return;
  for (auto& [replica, peer] : peers_) {
    if (peer.instance == instance) peer.advertised = false;
  }
}

void DesktopCookieSync::Impl::MarkComplete(const EpochRef& epoch, const std::string& replica) {
  std::lock_guard lock(mu_);
  if (epoch_ != epoch) return;
  const auto it = peers_.find(replica);
  if (it == peers_.end()) return;
  it->second.warm_complete = true;
  it->second.last_sync_at = Now();
}

void DesktopCookieSync::Impl::ScheduleHandshakes(const EpochRef& epoch) {
  std::vector<std::string> start;
  {
    std::lock_guard lock(mu_);
    const auto now = Clock::now();
    while (!outgoing_attempts_.empty() && now - outgoing_attempts_.front() >= std::chrono::minutes(1)) {
      outgoing_attempts_.pop_front();
    }
    std::size_t active = std::count_if(peers_.begin(), peers_.end(), [](const auto& item) { return item.second.handshaking; });
    for (auto& [replica, peer] : peers_) {
      if (!peer.advertised || peer.handshaking || peer.outgoing || !peer.incoming.empty()) continue;
      if (now < peer.next_attempt) continue;
      // One session per pair: the smaller replica initiates; the other only
      // after the fallback delay with no session formed.
      const bool designated = epoch->replica < replica;
      if (!designated && now - peer.first_seen < config_.timings.initiator_fallback) continue;
      if (outgoing_attempts_.size() >= kHandshakesPerMinute || active >= kConcurrentHandshakes) break;
      peer.handshaking = true;
      ++active;
      outgoing_attempts_.push_back(now);
      start.push_back(replica);
    }
  }
  for (const auto& replica : start) Spawn(&workers_, [this, epoch, replica] { Handshake(epoch, replica); });
}

void DesktopCookieSync::Impl::Backoff(Peer* peer, const std::string& error) {
  peer->failures = std::min(peer->failures + 1, 16);
  auto delay = config_.timings.backoff_min;
  for (int i = 1; i < peer->failures && delay < config_.timings.backoff_max; ++i) delay *= 2;
  peer->next_attempt = Clock::now() + std::min(delay, config_.timings.backoff_max);
  peer->last_error = error;
}

Json DesktopCookieSync::Impl::Status() const {
  std::lock_guard lock(mu_);
  Json out = {{"platform", config_.platform}};
  const bool hosted = desired_ && desired_->hosted;
  const bool signed_in = desired_ && desired_->signed_in;
  out["signedIn"] = signed_in;
  if (hosted || !config_.discovery || !store_) {
    out["supported"] = false;
    out["reason"] = hosted ? "embedded" : !config_.discovery ? "mdns-unavailable" : "cookies-unavailable";
    return out;
  }
  out["peers"] = Json::array();
  if (!signed_in) {
    out["supported"] = true;
    out["state"] = "signed-out";
    return out;
  }
  if (!epoch_) {
    out["supported"] = supported_;
    out["state"] = reason_.empty() ? "starting" : "unavailable";
    if (!reason_.empty()) out["reason"] = reason_;
    return out;
  }
  out["supported"] = true;
  out["state"] = warm_done_ ? "running" : "warming";
  out["warming"] = !warm_done_;
  out["replica"] = epoch_->replica;
  out["port"] = port_;
  const auto now = Clock::now();
  bool skew = false;
  for (const auto& [replica, peer] : peers_) {
    const bool outgoing = peer.outgoing && !peer.outgoing->ended;
    const bool incoming = !peer.incoming.empty();
    const char* state = outgoing || incoming ? "connected"
                        : peer.handshaking ? "handshaking"
                        : !peer.advertised ? "lost"
                        : peer.failures > 0 && now < peer.next_attempt ? "backoff" : "waiting";
    Json item = {{"replica", replica}, {"state", state},
                 {"lastSyncAt", peer.last_sync_at ? Json(peer.last_sync_at) : Json(nullptr)},
                 {"lastError", peer.last_error.empty() ? Json(nullptr) : Json(peer.last_error)}};
    if (outgoing || incoming) item["role"] = outgoing ? "initiator" : "responder";
    if (!peer.platform.empty()) item["platform"] = peer.platform;
    if (!peer.name.empty()) item["name"] = peer.name;
    skew = skew || peer.last_error == "CLOCK_SKEW";
    out["peers"].push_back(std::move(item));
  }
  out["clockSkew"] = skew;
  out["store"] = store_->Status();
  return out;
}

}  // namespace kelpie
