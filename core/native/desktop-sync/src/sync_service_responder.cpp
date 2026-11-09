// The responder: hello, auth (single use) and the encrypted exchange with its
// long-poll pull and push merge. Runs on listener worker threads.
#include <algorithm>
#include <cstdlib>

#include "sync_service.h"

#include "base64url.h"
#include "protocol.h"

namespace kelpie {
namespace {

using desktop_sync::ErrorReply;
using desktop_sync::SyncReply;
using account::AccountFailure;

constexpr std::size_t kMaxPending = 8;
constexpr auto kPendingTtl = std::chrono::seconds(60);
constexpr std::int64_t kMaxPullWait = 25000;

std::optional<std::uint64_t> Unsigned(const Json& value) {
  std::uint64_t out = 0;
  if (!sync::ReadUnsigned(value, &out)) return std::nullopt;
  return out;
}

// Refusal for a UOA failure while answering /auth.
SyncReply UoaRefusal(const AccountFailure& failure) {
  if (failure.status == 409) return ErrorReply(401, "SYNC_SESSION");
  return ErrorReply(503, "UOA_UNAVAILABLE");
}

}  // namespace

SyncReply DesktopCookieSync::Impl::Hello(const std::string& body, const std::string&) {
  const Json message = Json::parse(body, nullptr, false);
  std::string reason;
  const auto hello = desktop_sync::ParseHello("hello", message, &reason);
  if (!hello) return ErrorReply(400, "INVALID_MESSAGE");
  const std::int64_t now = Now();
  EpochRef epoch;
  {
    std::lock_guard lock(mu_);
    epoch = epoch_;
    if (!Live(epoch)) return ErrorReply(503, "UNAVAILABLE");
    if (hello->side.replica == epoch->replica) return ErrorReply(400, "INVALID_MESSAGE");
    const auto accepted = sync::AcceptedAccountHints(epoch->subject, now);
    if (std::find(accepted.begin(), accepted.end(), hello->hint) == accepted.end()) {
      return ErrorReply(409, "ACCOUNT_MISMATCH");  // before any UOA call
    }
    // An unproven hello never creates a peer: only one already discovered
    // through mDNS is annotated.
    const auto known = peers_.find(hello->side.replica);
    if (!desktop_sync::WithinClockSkew(hello->now, now)) {
      if (known != peers_.end()) known->second.last_error = "CLOCK_SKEW";
      return ErrorReply(409, "CLOCK_SKEW");
    }
    // One session per pair: the designated initiator (smaller replica) keeps its own.
    if (known != peers_.end() && known->second.outgoing && !known->second.outgoing->ended &&
        epoch->replica < hello->side.replica) {
      return ErrorReply(409, "SESSION_EXISTS");
    }
  }

  auto pending = std::make_unique<Pending>();
  pending->key = desktop_sync::EcdhKey::Generate();
  const auto& public_key = pending->key->PublicKey();
  pending->responder = {epoch->replica, sync::Base64UrlEncode(public_key.data(), public_key.size()),
                        desktop_sync::RandomToken(32)};
  pending->initiator = hello->side;
  pending->platform = hello->platform;
  pending->name = hello->name;
  pending->created = Clock::now();
  pending->id = desktop_sync::RandomToken(32);
  pending->challenge = desktop_sync::Challenge(pending->initiator, pending->responder);
  pending->epoch = epoch;
  pending->expires = Clock::now() + kPendingTtl;
  const Json reply = {{"v", sync::kProtocolVersion},
                      {"replica", epoch->replica},
                      {"now", now},
                      {"platform", config_.platform},
                      {"name", desktop_sync::HelloName(config_.device_name)},
                      {"key", pending->responder.key},
                      {"nonce", pending->responder.nonce},
                      {"handshakeId", pending->id},
                      {"expiresAt", now + std::chrono::duration_cast<std::chrono::milliseconds>(kPendingTtl).count()}};
  std::lock_guard lock(mu_);
  if (epoch_ != epoch) return ErrorReply(503, "UNAVAILABLE");
  pending_.push_back(std::move(pending));
  while (pending_.size() > kMaxPending) pending_.pop_front();  // a new handshake evicts the oldest
  return {200, reply};
}

SyncReply DesktopCookieSync::Impl::Auth(const std::string& body) {
  const Json message = Json::parse(body, nullptr, false);
  if (!sync::ValidateMessage("auth", message).empty()) return ErrorReply(400, "INVALID_MESSAGE");
  const std::string id = message.at("handshakeId").get<std::string>();
  std::unique_ptr<Pending> pending;
  {
    // The first /auth for a handshake consumes it, whatever the outcome.
    std::lock_guard lock(mu_);
    const auto it = std::find_if(pending_.begin(), pending_.end(), [&](const auto& item) { return item->id == id; });
    if (it != pending_.end()) {
      pending = std::move(*it);
      pending_.erase(it);
    }
  }
  if (!pending || Clock::now() >= pending->expires || !Live(pending->epoch)) return ErrorReply(401, "SYNC_SESSION");
  const EpochRef epoch = pending->epoch;
  const auto cancelled = CancelledFor(epoch);
  const auto with_uoa = [&](auto&& call) -> std::optional<SyncReply> {
    if (!uoa_.Acquire(std::chrono::seconds(10), cancelled)) return ErrorReply(503, "UOA_BUSY");
    struct Release {
      desktop_sync::UoaGate& gate;
      ~Release() { gate.Release(); }
    } release{uoa_};
    try {
      call();
    } catch (const AccountFailure& failure) {
      return UoaRefusal(failure);
    } catch (...) {
      return ErrorReply(503, "UOA_UNAVAILABLE");
    }
    return std::nullopt;
  };
  bool active = false;
  if (auto refusal = with_uoa([&] {
        active = config_.account->ValidatePairTicket(message.at("ticket").get<std::string>(), pending->challenge,
                                                     desktop_sync::InitiatorClientId(pending->initiator.replica),
                                                     epoch->account_generation);
      })) {
    return *refusal;
  }
  if (!active) {
    std::lock_guard lock(mu_);
    if (const auto peer = peers_.find(pending->initiator.replica); peer != peers_.end()) {
      peer->second.last_error = "AUTH_FAILED";
    }
    return ErrorReply(403, "AUTH_FAILED");
  }
  std::string ticket;
  if (auto refusal = with_uoa([&] {
        ticket = config_.account->IssuePairTicket(pending->challenge, desktop_sync::ResponderClientId(epoch->replica),
                                                  epoch->account_generation);
      })) {
    return *refusal;
  }
  const auto keys = desktop_sync::DeriveKeys(*pending->key, pending->initiator.key, pending->challenge);
  pending->key.reset();  // ephemeral keys are discarded after derivation
  if (!keys) return ErrorReply(400, "INVALID_MESSAGE");

  auto session = std::make_shared<Incoming>();
  session->id = pending->id;
  session->keys = *keys;
  session->peer_replica = pending->initiator.replica;
  session->epoch = epoch;
  session->expires = Clock::now() + config_.timings.session_lifetime;
  std::shared_ptr<Outgoing> superseded;
  {
    std::lock_guard lock(mu_);
    if (epoch_ != epoch || !Live(epoch)) return ErrorReply(401, "SYNC_SESSION");
    // The account is proven: only now does the initiator become a peer.
    Peer& peer = peers_[session->peer_replica];
    if (peer.replica.empty()) {
      peer.replica = session->peer_replica;
      peer.first_seen = pending->created;
      peer.in_warmup_window = !warm_done_ && pending->created - epoch->opened < config_.timings.warmup_window;
    }
    peer.platform = pending->platform;
    peer.name = pending->name;
    if (peer.outgoing && !peer.outgoing->ended) {
      // One session per pair: the designated initiator keeps its own.
      if (epoch->replica < session->peer_replica) return ErrorReply(409, "SESSION_EXISTS");
      superseded = peer.outgoing;
    }
    if (!peer.incoming.empty()) incoming_.erase(peer.incoming);
    peer.incoming = session->id;
    peer.failures = 0;
    peer.last_error.clear();
    incoming_[session->id] = session;  // keys installed exactly once
  }
  if (superseded) EndOutgoing(superseded, "SUPERSEDED");
  Log("cookie-sync: session established (responder)");
  return {200, {{"ticket", ticket},
                {"sessionExpiresAt",
                 Now() + std::chrono::duration_cast<std::chrono::milliseconds>(config_.timings.session_lifetime).count()}}};
}

std::shared_ptr<DesktopCookieSync::Impl::Incoming> DesktopCookieSync::Impl::FindIncoming(const std::string& id) const {
  std::lock_guard lock(mu_);
  const auto it = incoming_.find(id);
  if (it == incoming_.end() || Clock::now() >= it->second->expires || it->second->epoch != epoch_ ||
      !Live(it->second->epoch)) {
    return nullptr;
  }
  return it->second;
}

bool DesktopCookieSync::Impl::SessionLive(const std::string& session_id) { return FindIncoming(session_id) != nullptr; }

SyncReply DesktopCookieSync::Impl::Exchange(const std::string& session_id, const std::string& body) {
  const auto session = FindIncoming(session_id);
  if (!session) return ErrorReply(401, "SYNC_SESSION");
  const Json message = Json::parse(body, nullptr, false);
  if (!sync::ValidateMessage("exchange", message).empty()) return ErrorReply(400, "INVALID_MESSAGE");
  const std::uint64_t seq = *Unsigned(message.at("seq"));
  {
    std::lock_guard lock(session->window_mutex);
    if (!session->window.Acceptable(seq)) return ErrorReply(400, "REPLAY");
  }
  const auto plain = desktop_sync::OpenBox(session->keys, desktop_sync::Direction::kRequest, session->id, seq,
                                           message.at("box").get<std::string>());
  if (!plain) return ErrorReply(400, "INVALID_BOX");
  {
    std::lock_guard lock(session->window_mutex);
    if (!session->window.Acceptable(seq)) return ErrorReply(400, "REPLAY");
    session->window.Accept(seq);
  }
  const Json inner = Json::parse(*plain, nullptr, false);
  if (!inner.is_object() || inner.value("replica", std::string()) != session->peer_replica) {
    return ErrorReply(400, "INVALID_MESSAGE");
  }
  const std::string op = inner.value("op", std::string());
  std::optional<Json> response;
  if (op == "pull") {
    response = LongPoll(inner, session);
  } else if (op == "push") {
    response = AcceptPush(inner, session);
  } else {
    return ErrorReply(400, "INVALID_MESSAGE");
  }
  if (!response) return ErrorReply(503, "UNAVAILABLE");
  const auto box = desktop_sync::SealBox(session->keys, desktop_sync::Direction::kResponse, session->id, seq,
                                         response->dump());
  if (!box) return ErrorReply(500, "INTERNAL");
  return {200, {{"seq", seq}, {"box", *box}}};
}

std::optional<Json> DesktopCookieSync::Impl::LongPoll(const Json& pull, const std::shared_ptr<Incoming>& session) {
  const auto since = pull.find("since");
  if (since == pull.end() || !since->is_object() || !since->contains("seq") || !Unsigned((*since)["seq"])) {
    return std::nullopt;
  }
  const auto wait_field = pull.find("wait");
  const std::int64_t wait = wait_field != pull.end() && wait_field->is_number_integer()
                                ? std::clamp<std::int64_t>(wait_field->get<std::int64_t>(), 0, kMaxPullWait) : 0;
  const std::uint64_t after = since->value("replica", std::string()) == session->epoch->replica
                                  ? *Unsigned((*since)["seq"]) : 0;
  const auto deadline = Clock::now() + std::chrono::milliseconds(wait);
  const auto cancelled = CancelledFor(session->epoch);
  while (true) {
    std::uint64_t counter;
    {
      std::lock_guard lock(mu_);
      counter = change_counter_;
    }
    auto response = store_->AnswerPull(pull, Now(), cancelled);
    if (!response) return std::nullopt;
    const Json& value = *response;
    // Answer at once when there is anything to say, otherwise when the feed
    // moves or the wait runs out.
    const bool ready = !value.value("records", Json::array()).empty() || value.value("more", false) ||
                       value.value("warming", false) || value.value("incomplete", false) ||
                       value.value("seq", std::uint64_t{0}) != after || Clock::now() >= deadline ||
                       !Live(session->epoch);
    if (ready) return response;
    std::unique_lock lock(mu_);
    changed_.wait_until(lock, deadline, [&] { return change_counter_ != counter || !Live(session->epoch); });
  }
}

std::optional<Json> DesktopCookieSync::Impl::AcceptPush(const Json& push, const std::shared_ptr<Incoming>& session) {
  const auto seq = push.find("seq");
  const auto records = push.find("records");
  const auto more = push.find("more");
  if (seq == push.end() || !Unsigned(*seq) || records == push.end() || !records->is_array() || more == push.end() ||
      !more->is_boolean()) {
    return std::nullopt;
  }
  const auto committed = store_->Merge(*records, {{"replica", session->peer_replica}, {"seq", *seq}}, Now(),
                                       CancelledFor(session->epoch));
  if (!committed) return std::nullopt;
  if (!more->get<bool>()) MarkComplete(session->epoch, session->peer_replica);
  const auto watermark = store_->Watermark(session->peer_replica);
  if (!watermark) return std::nullopt;
  return Json{{"yourWatermark", *watermark}};
}

}  // namespace kelpie
