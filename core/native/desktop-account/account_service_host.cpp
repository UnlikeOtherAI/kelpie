#include "account_service.h"
#include <utility>

namespace kelpie::account {
void AccountService::UseHostSession(std::shared_ptr<HostSession> session) {
  Reset();
  std::lock_guard lock(mutex_);
  host_session_ = std::move(session);
  host_state_ = {};
  host_pending_ = false;
}

void AccountService::PollHostSession() {
  std::shared_ptr<HostSession> session;
  HostSessionState previous;
  {
    std::lock_guard lock(mutex_);
    session = host_session_;
    previous = host_state_;
  }
  if (!session) return;
  HostSessionState next;
  try {
    if (session->state) next = session->state();
    if (!next.subject.empty() && next.epoch.empty()) next = {};
  } catch (...) { next = {}; }
  if (next == previous) return;
  Reset();
  std::lock_guard lock(mutex_);
  host_state_ = std::move(next);
  host_pending_ = !host_state_.subject.empty();
}
}
