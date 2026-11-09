#pragma once

#include <cstdint>
#include <string>
#include <vector>

#include <nlohmann/json.hpp>

namespace kelpie::sync {

inline constexpr int kProtocolVersion = 1;
inline constexpr std::int64_t kMaxClockSkewMillis = 2 * 60 * 1000;

// Checks the shape of an unauthenticated or envelope message. `kind` is one of
// "hello", "hello-reply", "auth", "auth-reply" or "exchange". Returns an empty
// string when valid, otherwise a short reason. Never echoes field values.
std::string ValidateMessage(const std::string& kind, const nlohmann::json& message);

// base64url(SHA-256(transcript)) — 43 characters, UOA's challenge format.
// Input: {"initiator":{"replica","key","nonce"},"responder":{…}}.
std::string TranscriptChallenge(const nlohmann::json& hello_pair);

// The account hint for the UTC day containing `now_millis`, and the set a
// device accepts (yesterday, today, tomorrow).
std::string AccountHint(const std::string& subject, std::int64_t now_millis);
std::vector<std::string> AcceptedAccountHints(const std::string& subject, std::int64_t now_millis);

// "YYYY-MM-DD" for the UTC day containing `now_millis`.
std::string UtcDate(std::int64_t now_millis);

}  // namespace kelpie::sync
