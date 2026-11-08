#pragma once
#include <functional>
#include <string>
#include "account_protocol.h"

namespace kelpie::account {
struct HostSessionState {
  std::string subject;
  // Changes for sign-out, revocation or a replacement session, even for the same subject.
  std::string epoch;
  bool operator==(const HostSessionState& other) const {
    return subject == other.subject && epoch == other.epoch;
  }
};

// Callbacks must be safe on account worker threads. The host owns refresh,
// credential storage and revocation. No credential is copied into Kelpie.
struct HostSession {
  std::function<HostSessionState()> state;
  std::function<AccountResponse(const std::string&, const std::string&,
                               const std::string&, const std::string&)> request;
  std::function<void()> sign_in;
  std::function<void()> sign_out;
};
}
