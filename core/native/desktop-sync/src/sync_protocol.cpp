#include "sync_protocol.h"

#include <algorithm>
#include <cstdlib>

#include "account_service.h"
#include "base64url.h"
#include "protocol.h"

namespace kelpie::desktop_sync {
namespace {

using nlohmann::json;
using account::AccountFailure;

std::string Field(const json& message, const char* name) {
  const auto it = message.find(name);
  return it != message.end() && it->is_string() ? it->get<std::string>() : std::string();
}

std::string UoaErrorCode(const AccountFailure& failure) {
  if (failure.status == 409) return "STALE";
  if (failure.status == 401) return "UOA_SESSION";
  if (failure.status == 0 || failure.status == 408 || failure.status == 429 || failure.status >= 500) {
    return "UOA_UNAVAILABLE";
  }
  return "UOA_REFUSED";
}

// Runs one UOA call under the concurrency gate. Returns an error code or "".
template <typename Call>
std::string WithUoa(const InitiatorRequest& request, Call&& call) {
  const auto cancelled = [&] { return !request.live() || (request.aborts && request.aborts->aborted()); };
  if (!request.gate->Acquire(std::chrono::seconds(15), cancelled)) return cancelled() ? "STALE" : "UOA_BUSY";
  struct Release {
    UoaGate* gate;
    ~Release() { gate->Release(); }
  } release{request.gate};
  try {
    call();
  } catch (const AccountFailure& failure) {
    return UoaErrorCode(failure);
  } catch (...) {
    return "UOA_UNAVAILABLE";
  }
  return request.live() ? "" : "STALE";
}

// The responder's refusal code, or a generic one for its HTTP status.
std::string ReplyError(const ClientReply& reply) {
  if (!reply.delivered) return "UNREACHABLE";
  const std::string code = reply.body.is_object() ? Field(reply.body, "error") : std::string();
  if (!code.empty() && code.size() <= 32 &&
      std::all_of(code.begin(), code.end(), [](char c) { return (c >= 'A' && c <= 'Z') || c == '_'; })) {
    return code;
  }
  return "HTTP_" + std::to_string(reply.status);
}

}  // namespace

std::string RandomToken(std::size_t bytes) {
  const Bytes random = RandomBytes(bytes);
  return sync::Base64UrlEncode(random.data(), random.size());
}

std::string InitiatorClientId(const std::string& replica) { return "kelpie-sync:i:" + replica; }
std::string ResponderClientId(const std::string& replica) { return "kelpie-sync:r:" + replica; }

std::string Challenge(const HelloSide& initiator, const HelloSide& responder) {
  return sync::TranscriptChallenge(
      {{"initiator", {{"replica", initiator.replica}, {"key", initiator.key}, {"nonce", initiator.nonce}}},
       {"responder", {{"replica", responder.replica}, {"key", responder.key}, {"nonce", responder.nonce}}}});
}

std::optional<PeerHello> ParseHello(const std::string& kind, const json& message, std::string* reason) {
  *reason = sync::ValidateMessage(kind, message);
  if (!reason->empty()) return std::nullopt;
  PeerHello hello;
  hello.side = {Field(message, "replica"), Field(message, "key"), Field(message, "nonce")};
  const auto key = sync::Base64UrlDecode(hello.side.key);
  if (!key || !IsValidPublicKey(*key)) {
    *reason = "invalid key";
    return std::nullopt;
  }
  hello.now = message.at("now").get<std::int64_t>();
  hello.platform = Field(message, "platform");
  hello.name = Field(message, "name");
  hello.hint = Field(message, "hint");
  hello.handshake_id = Field(message, "handshakeId");
  if (message.contains("expiresAt")) hello.expires_at = message.at("expiresAt").get<std::int64_t>();
  return hello;
}

std::optional<SessionKeys> DeriveKeys(const EcdhKey& own, const std::string& peer_key, const std::string& challenge) {
  const auto key = sync::Base64UrlDecode(peer_key);
  const auto transcript = sync::Base64UrlDecode(challenge);
  if (!key || !transcript || transcript->size() != 32) return std::nullopt;
  const auto secret = own.SharedSecret(*key);
  if (!secret) return std::nullopt;
  return DeriveSessionKeys(*secret, *transcript);
}

std::string HelloName(const std::string& device_name) {
  std::string out;
  for (std::size_t i = 0; i < device_name.size();) {
    const unsigned char lead = static_cast<unsigned char>(device_name[i]);
    const std::size_t width = lead < 0x80 ? 1 : (lead >> 5) == 0x6 ? 2 : (lead >> 4) == 0xe ? 3 : (lead >> 3) == 0x1e ? 4 : 0;
    if (width == 0 || i + width > device_name.size()) break;
    if (width == 1 && (lead < 0x20 || lead == 0x7f)) { ++i; continue; }
    if (out.size() + width > 64) break;
    out.append(device_name, i, width);
    i += width;
  }
  return out;
}

bool UoaGate::Acquire(std::chrono::milliseconds max_wait, const std::function<bool()>& cancelled) {
  std::unique_lock lock(mutex_);
  const auto until = Clock::now() + max_wait;
  while (free_ == 0) {
    if (cancelled() || Clock::now() >= until) return false;
    ready_.wait_for(lock, std::chrono::milliseconds(50));
  }
  if (cancelled()) return false;
  --free_;
  return true;
}

void UoaGate::Release() {
  {
    std::lock_guard lock(mutex_);
    ++free_;
  }
  ready_.notify_one();
}

bool AbortSet::Add(const std::shared_ptr<SyncClient>& client) {
  std::lock_guard lock(mutex_);
  if (aborted_) return false;
  clients_.push_back(client);
  return true;
}

void AbortSet::Remove(const std::shared_ptr<SyncClient>& client) {
  std::lock_guard lock(mutex_);
  clients_.erase(std::remove(clients_.begin(), clients_.end(), client), clients_.end());
}

void AbortSet::AbortAll() {
  std::vector<std::shared_ptr<SyncClient>> clients;
  {
    std::lock_guard lock(mutex_);
    aborted_ = true;
    clients.swap(clients_);
  }
  for (const auto& client : clients) client->Stop();
}

InitiatorResult RunInitiatorHandshake(const InitiatorRequest& request) {
  InitiatorResult result;
  const auto own = EcdhKey::Generate();
  const HelloSide mine{request.replica, sync::Base64UrlEncode(own->PublicKey().data(), own->PublicKey().size()),
                       RandomToken(32)};
  const json hello = {{"v", sync::kProtocolVersion}, {"replica", mine.replica}, {"hint", request.hint},
                      {"now", request.now_millis()}, {"platform", request.platform},
                      {"name", HelloName(request.name)}, {"key", mine.key}, {"nonce", mine.nonce}};

  // Try each permitted address in preference order until one answers.
  std::shared_ptr<SyncClient> client;
  ClientReply reply;
  IpAddress target;
  for (const auto& address : OrderTargets(request.addresses, EnumerateInterfaces())) {
    if (!request.live()) return {std::nullopt, "STALE"};
    auto candidate = std::make_shared<SyncClient>(address, request.port);
    if (!request.aborts->Add(candidate)) return {std::nullopt, "STALE"};
    reply = candidate->Post(kHelloPath, hello, std::chrono::seconds(5), {}, 16 * 1024);
    if (reply.delivered) {
      client = candidate;
      target = address;
      break;
    }
    request.aborts->Remove(candidate);
  }
  if (!client) return {std::nullopt, "UNREACHABLE"};
  struct Unregister {
    AbortSet* set;
    std::shared_ptr<SyncClient> client;
    ~Unregister() { set->Remove(client); }
  } unregister{request.aborts, client};
  if (reply.status != 200) return {std::nullopt, ReplyError(reply)};

  std::string reason;
  const auto peer = ParseHello("hello-reply", reply.body, &reason);
  if (!peer || peer->side.replica != request.expected_replica) return {std::nullopt, "INVALID_REPLY"};
  result.peer_platform = peer->platform;
  result.peer_name = peer->name;
  if (std::llabs(peer->now - request.now_millis()) > kMaxSkewMillis) {
    result.error = "CLOCK_SKEW";
    return result;
  }
  const std::string challenge = Challenge(mine, peer->side);

  std::string ticket;
  result.error = WithUoa(request, [&] {
    ticket = request.account->IssuePairTicket(challenge, InitiatorClientId(mine.replica), request.generation);
  });
  if (!result.error.empty()) return result;

  const ClientReply auth = client->Post(kAuthPath, {{"handshakeId", peer->handshake_id}, {"ticket", ticket}},
                                        std::chrono::seconds(30), {}, 16 * 1024);
  if (auth.status != 200 || !auth.delivered) {
    result.error = ReplyError(auth);
    return result;
  }
  if (!sync::ValidateMessage("auth-reply", auth.body).empty()) {
    result.error = "INVALID_REPLY";
    return result;
  }
  bool active = false;
  result.error = WithUoa(request, [&] {
    active = request.account->ValidatePairTicket(Field(auth.body, "ticket"), challenge,
                                                 ResponderClientId(peer->side.replica), request.generation);
  });
  if (!result.error.empty()) return result;
  if (!active) {
    result.error = "AUTH_FAILED";
    return result;
  }
  const auto keys = DeriveKeys(*own, peer->side.key, challenge);
  if (!keys) {
    result.error = "INVALID_REPLY";
    return result;
  }
  EstablishedSession session;
  session.id = peer->handshake_id;
  session.keys = *keys;
  session.peer_replica = peer->side.replica;
  session.peer_platform = peer->platform;
  session.peer_name = peer->name;
  session.target = target;
  session.port = request.port;
  session.expires_at = auth.body.at("sessionExpiresAt").get<std::int64_t>();
  result.session = std::move(session);
  return result;
}

ExchangeResult InitiatorExchange(const EstablishedSession& session, SyncClient& client, std::uint64_t seq,
                                 const json& message, std::chrono::seconds read_timeout) {
  const auto box = SealBox(session.keys, Direction::kRequest, session.id, seq, message.dump());
  if (!box) return {std::nullopt, "CRYPTO"};
  const ClientReply reply = client.Post(kExchangePath, {{"seq", seq}, {"box", *box}}, read_timeout,
                                        {{kSessionHeader, session.id}});
  if (!reply.delivered || reply.status != 200) return {std::nullopt, ReplyError(reply)};
  if (!sync::ValidateMessage("exchange", reply.body).empty() || reply.body.at("seq") != seq) {
    return {std::nullopt, "INVALID_REPLY"};
  }
  const auto plain = OpenBox(session.keys, Direction::kResponse, session.id, seq, Field(reply.body, "box"));
  if (!plain) return {std::nullopt, "INVALID_BOX"};
  auto parsed = json::parse(*plain, nullptr, false);
  if (parsed.is_discarded() || !parsed.is_object()) return {std::nullopt, "INVALID_REPLY"};
  return {std::move(parsed), ""};
}

}  // namespace kelpie::desktop_sync
