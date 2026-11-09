#pragma once

// Handshake and exchange steps shared by the sync service and its tests:
// hello construction and checks, the mutual UOA proof, session key
// derivation and one encrypted initiator exchange.

#include <atomic>
#include <chrono>
#include <condition_variable>
#include <cstdint>
#include <functional>
#include <memory>
#include <mutex>
#include <optional>
#include <string>
#include <vector>

#include <nlohmann/json.hpp>

#include "sync_channel.h"
#include "sync_client.h"
#include "sync_crypto.h"

namespace kelpie::account {
class AccountService;
}

namespace kelpie::desktop_sync {

using Clock = std::chrono::steady_clock;

inline constexpr std::int64_t kMaxSkewMillis = 2 * 60 * 1000;

// |remote - local| <= kMaxSkewMillis without signed overflow, for any two
// int64 clocks a peer can send.
bool WithinClockSkew(std::int64_t remote, std::int64_t local);
// Milliseconds from `now` until `later`, clamped to [0, cap] without overflow.
std::int64_t MillisUntil(std::int64_t later, std::int64_t now, std::int64_t cap);
inline constexpr const char* kHelloPath = "/v1/sync/hello";
inline constexpr const char* kAuthPath = "/v1/sync/auth";
inline constexpr const char* kExchangePath = "/v1/sync/exchange";
inline constexpr const char* kSessionHeader = "X-Kelpie-Sync-Session";

std::string RandomToken(std::size_t bytes);  // base64url of CSPRNG bytes
std::string InitiatorClientId(const std::string& replica);
std::string ResponderClientId(const std::string& replica);

// One side of the transcript, exactly as sent (base64url text).
struct HelloSide {
  std::string replica, key, nonce;
};
std::string Challenge(const HelloSide& initiator, const HelloSide& responder);

struct PeerHello {
  HelloSide side;
  std::int64_t now = 0;
  std::string platform, name, hint, handshake_id;
  std::int64_t expires_at = 0;
};
// Validates `kind` ("hello" or "hello-reply") with core-sync and checks that
// the key is a real P-256 point. nullopt with a reason otherwise.
std::optional<PeerHello> ParseHello(const std::string& kind, const nlohmann::json& message, std::string* reason);

// ECDH with the peer key, then HKDF over the transcript.
std::optional<SessionKeys> DeriveKeys(const EcdhKey& own, const std::string& peer_key, const std::string& challenge);

// A printable device label of at most 64 bytes without splitting UTF-8.
std::string HelloName(const std::string& device_name);

// Counting gate for concurrent UOA calls (2 in total).
class UoaGate {
 public:
  explicit UoaGate(int slots) : free_(slots) {}
  bool Acquire(std::chrono::milliseconds max_wait, const std::function<bool()>& cancelled);
  void Release();
  void WakeAll() { ready_.notify_all(); }

 private:
  std::mutex mutex_;
  std::condition_variable ready_;
  int free_;
};

// The clients a handshake or session is using, so teardown can abort them.
class AbortSet {
 public:
  bool Add(const std::shared_ptr<SyncClient>& client);  // false once aborted
  void Remove(const std::shared_ptr<SyncClient>& client);
  void AbortAll();
  bool aborted() const { return aborted_; }

 private:
  std::mutex mutex_;
  std::vector<std::shared_ptr<SyncClient>> clients_;
  std::atomic<bool> aborted_{false};
};

// An established, keyed session as the initiator holds it.
struct EstablishedSession {
  std::string id;  // the handshakeId
  SessionKeys keys;
  std::string peer_replica, peer_platform, peer_name;
  IpAddress target;
  int port = 0;
  std::int64_t expires_at = 0;  // the responder's sessionExpiresAt (Unix ms)
};

struct InitiatorRequest {
  account::AccountService* account = nullptr;
  std::uint64_t generation = 0;
  std::string replica, platform, name, hint;
  std::vector<std::string> addresses;
  int port = 0;
  std::string expected_replica;
  std::function<std::int64_t()> now_millis;
  std::function<bool()> live;  // the account generation and service are still current
  UoaGate* gate = nullptr;
  AbortSet* aborts = nullptr;
};

struct InitiatorResult {
  std::optional<EstablishedSession> session;
  std::string error;  // a stable code: UNREACHABLE, CLOCK_SKEW, ACCOUNT_MISMATCH, AUTH_FAILED, …
  std::string peer_platform, peer_name;
};

// hello → initiator ticket → auth → validate the responder ticket → keys.
// Blocking; returns early once `live` turns false or the abort set fires.
InitiatorResult RunInitiatorHandshake(const InitiatorRequest& request);

struct ExchangeResult {
  std::optional<nlohmann::json> plaintext;  // the decrypted response object
  std::string error;                        // SYNC_SESSION, UNREACHABLE, REPLAY, …
};
// Seals `message` as request `seq`, posts it and opens the response.
ExchangeResult InitiatorExchange(const EstablishedSession& session, SyncClient& client, std::uint64_t seq,
                                 const nlohmann::json& message, std::chrono::seconds read_timeout);

}  // namespace kelpie::desktop_sync
