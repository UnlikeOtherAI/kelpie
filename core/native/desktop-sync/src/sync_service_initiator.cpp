// The initiator: handshake attempts and the session's long-poll pull loop and
// push loop. Only the initiator sends requests.
#include "sync_service.h"

#include "protocol.h"

namespace kelpie {
namespace {

std::optional<std::uint64_t> Unsigned(const Json& value) {
  std::uint64_t out = 0;
  if (!sync::ReadUnsigned(value, &out)) return std::nullopt;
  return out;
}

bool ValidCursor(const Json& cursor) {
  return cursor.is_object() && cursor.contains("replica") && cursor["replica"].is_string() &&
         cursor.contains("seq") && Unsigned(cursor["seq"]);
}

bool ValidPullResponse(const Json& response, const std::string& peer) {
  return response.value("replica", std::string()) == peer && response.contains("records") &&
         response["records"].is_array() && response.contains("seq") && Unsigned(response["seq"]) &&
         response.value("more", Json()).is_boolean() && response.value("warming", Json()).is_boolean() &&
         response.value("incomplete", Json()).is_boolean() && ValidCursor(response.value("yourWatermark", Json()));
}

}  // namespace

void DesktopCookieSync::Impl::Handshake(EpochRef epoch, std::string replica) {
  desktop_sync::InitiatorRequest request;
  auto aborts = std::make_shared<desktop_sync::AbortSet>();
  {
    std::lock_guard lock(mu_);
    const auto peer = peers_.find(replica);
    if (epoch_ != epoch || peer == peers_.end()) return;
    request.addresses = peer->second.addresses;
    request.port = peer->second.port;
    handshake_aborts_.push_back(aborts);
  }
  request.account = config_.account;
  request.generation = epoch->account_generation;
  request.replica = epoch->replica;
  request.platform = config_.platform;
  request.name = config_.device_name;
  request.hint = sync::AccountHint(epoch->subject, Now());
  request.expected_replica = replica;
  request.now_millis = config_.now_millis;
  request.live = [this, epoch] { return Live(epoch); };
  request.gate = &uoa_;
  request.aborts = aborts.get();
  auto result = desktop_sync::RunInitiatorHandshake(request);
  {
    std::lock_guard lock(mu_);
    handshake_aborts_.erase(std::remove(handshake_aborts_.begin(), handshake_aborts_.end(), aborts),
                            handshake_aborts_.end());
    const auto peer = peers_.find(replica);
    if (epoch_ != epoch || peer == peers_.end()) return;
    peer->second.handshaking = false;
    if (!result.peer_platform.empty()) {
      peer->second.platform = result.peer_platform;
      peer->second.name = result.peer_name;
    }
    if (!result.session) {
      if (result.error != "STALE") Backoff(&peer->second, result.error);
      Log("cookie-sync: handshake failed: " + result.error);
      return;
    }
  }
  InstallOutgoing(epoch, replica, std::move(*result.session));
}

void DesktopCookieSync::Impl::InstallOutgoing(const EpochRef& epoch, const std::string& replica,
                                              desktop_sync::EstablishedSession channel) {
  auto session = std::make_shared<Outgoing>();
  // The responder's expiry, bounded by our own lifetime; any int64 it sends is safe here.
  const std::int64_t lifetime = config_.timings.session_lifetime.count();
  const std::int64_t remaining = std::max<std::int64_t>(desktop_sync::MillisUntil(channel.expires_at, Now(), lifetime), 1000);
  session->expires = Clock::now() + std::chrono::milliseconds(remaining);
  session->channel = std::move(channel);
  session->epoch = epoch;
  std::lock_guard lock(mu_);
  const auto peer = peers_.find(replica);
  if (epoch_ != epoch || !Live(epoch) || peer == peers_.end()) return;
  // The designated initiator's session already formed the other way round.
  if (!peer->second.incoming.empty() && !(epoch->replica < replica)) return;
  if (!peer->second.incoming.empty()) {
    incoming_.erase(peer->second.incoming);
    peer->second.incoming.clear();
  }
  peer->second.outgoing = session;
  peer->second.failures = 0;
  peer->second.last_error.clear();
  SpawnLocked(&session->workers, [this, session] { PullLoop(session); });
  SpawnLocked(&session->workers, [this, session] { PushLoop(session); });
  Log("cookie-sync: session established (initiator)");
}

bool DesktopCookieSync::Impl::SessionUsable(const std::shared_ptr<Outgoing>& session) const {
  return !session->ended && !session->aborts.aborted() && Clock::now() < session->expires && Live(session->epoch);
}

void DesktopCookieSync::Impl::EndOutgoing(const std::shared_ptr<Outgoing>& session, const std::string& error) {
  {
    std::lock_guard lock(mu_);
    if (session->ended) return;
    session->end_error = error;
    session->ended = true;
    woken_ = true;
  }
  session->aborts.AbortAll();
  changed_.notify_all();
  wake_.notify_all();
}

void DesktopCookieSync::Impl::PullLoop(std::shared_ptr<Outgoing> session) {
  auto client = std::make_shared<desktop_sync::SyncClient>(session->channel.target, session->channel.port);
  if (!session->aborts.Add(client)) return;
  const std::string& peer = session->channel.peer_replica;
  const auto cancelled = CancelledFor(session->epoch);
  const auto pause = [&](std::chrono::milliseconds duration) {
    std::unique_lock lock(mu_);
    changed_.wait_for(lock, duration, [&] { return !SessionUsable(session); });
  };
  const auto pull_wait = std::chrono::duration_cast<std::chrono::milliseconds>(config_.timings.pull_wait).count();
  bool first = true;
  while (SessionUsable(session)) {
    const auto since = store_->Watermark(peer);
    if (!since) break;
    // The first pull answers at once, so the push loop learns its watermark.
    const Json pull = {{"op", "pull"}, {"replica", session->epoch->replica}, {"since", *since},
                       {"wait", first ? 0 : pull_wait}};
    first = false;
    const auto result = desktop_sync::InitiatorExchange(session->channel, *client, session->next_seq++, pull,
                                                        std::chrono::seconds(pull_wait / 1000 + 10));
    if (!SessionUsable(session)) break;
    if (!result.plaintext || !ValidPullResponse(*result.plaintext, peer)) {
      EndOutgoing(session, result.plaintext ? "INVALID_REPLY" : result.error);
      return;
    }
    const Json& response = *result.plaintext;
    {
      std::lock_guard lock(mu_);
      const Json& theirs = response["yourWatermark"];
      if (!session->watermark || theirs["replica"] != (*session->watermark)["replica"] ||
          *Unsigned(theirs["seq"]) > *Unsigned((*session->watermark)["seq"])) {
        session->watermark = theirs;
      }
    }
    changed_.notify_all();
    if (response["warming"] == true) {
      pause(std::chrono::seconds(2));
      continue;
    }
    const std::uint64_t seq = *Unsigned(response["seq"]);
    if (!response["records"].empty() || seq != *Unsigned((*since)["seq"])) {
      // Watermarks move only on commit; a failed merge re-pulls the same page.
      if (!store_->Merge(response["records"], {{"replica", peer}, {"seq", seq}}, Now(), cancelled)) {
        pause(std::chrono::seconds(2));
        continue;
      }
    }
    if (response["more"] == false && response["incomplete"] == false) MarkComplete(session->epoch, peer);
    if (response["incomplete"] == true && response["more"] == false) pause(std::chrono::seconds(5));
  }
  EndOutgoing(session, "");  // expiry: handshake again while the peer advertises
}

void DesktopCookieSync::Impl::PushLoop(std::shared_ptr<Outgoing> session) {
  auto client = std::make_shared<desktop_sync::SyncClient>(session->channel.target, session->channel.port);
  if (!session->aborts.Add(client)) return;
  const auto cancelled = CancelledFor(session->epoch);
  std::uint64_t seen = 0;
  bool now = true;  // the first watermark, and every page after a `more`
  while (SessionUsable(session)) {
    Json watermark;
    {
      std::unique_lock lock(mu_);
      changed_.wait_for(lock, std::chrono::seconds(30), [&] {
        return !SessionUsable(session) || (session->watermark && (now || change_counter_ != seen));
      });
      if (!SessionUsable(session)) break;
      if (!session->watermark || (!now && change_counter_ == seen)) continue;
      seen = change_counter_;
      watermark = *session->watermark;
      now = false;
    }
    const auto built = store_->BuildPush(watermark, Now(), cancelled);
    if (!built || !built->contains("push") || (*built)["push"].is_null()) continue;
    const Json push = (*built)["push"];
    const auto result = desktop_sync::InitiatorExchange(session->channel, *client, session->next_seq++, push,
                                                        std::chrono::seconds(30));
    if (!SessionUsable(session)) break;
    if (!result.plaintext || !ValidCursor(result.plaintext->value("yourWatermark", Json()))) {
      EndOutgoing(session, result.plaintext ? "INVALID_REPLY" : result.error);
      return;
    }
    {
      std::lock_guard lock(mu_);
      session->watermark = (*result.plaintext)["yourWatermark"];
      if (const auto peer = peers_.find(session->channel.peer_replica); peer != peers_.end()) {
        peer->second.last_sync_at = Now();
      }
    }
    if (push.value("more", false)) now = true;
  }
  EndOutgoing(session, "");
}

}  // namespace kelpie
