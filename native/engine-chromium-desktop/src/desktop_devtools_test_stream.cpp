#include "desktop_devtools.h"
#include <utility>
#include <vector>
#include "include/cef_task.h"
#include "include/cef_values.h"

namespace kelpie {
#if defined(KELPIE_WINDOWS_CEF_STREAM_PROBE)
bool DesktopDevToolsSession::InstallTestStream(CefRefPtr<CefBrowser> browser,
                                              TestStreamEventSink event,
                                              TestStreamDetachSink detached) {
  if (!browser || !event || !detached || !CefCurrentlyOn(TID_UI)) return false;
  if (!browser->GetHost()) return false;
  std::lock_guard<std::mutex> lock(mutex_);
  if (!browser_ || !browser_->IsSame(browser) || !registration_ || test_stream_event_ || !test_stream_acks_.empty() ||
      test_stream_ingress_ || test_stream_completions_) return false;
  test_stream_event_ = std::move(event);
  test_stream_detached_ = std::move(detached);
  test_stream_accepting_ = true;
  return true;
}

void DesktopDevToolsSession::CloseTestStreamIngress() {
  std::lock_guard<std::mutex> lock(mutex_);
  test_stream_accepting_ = false;
}

bool DesktopDevToolsSession::WaitTestStreamDrained(std::chrono::milliseconds timeout) {
  if (CefCurrentlyOn(TID_UI) || timeout <= std::chrono::milliseconds::zero() || timeout > std::chrono::seconds(5)) return false;
  std::unique_lock<std::mutex> lock(mutex_);
  return test_stream_drained_.wait_for(lock, timeout, [this] {
    return !test_stream_accepting_ && test_stream_ingress_ == 0 &&
        test_stream_acks_.empty() && test_stream_completions_ == 0;
  });
}

bool DesktopDevToolsSession::ReleaseTestStream() {
  TestStreamEventSink event;
  TestStreamDetachSink detached;
  {
    std::lock_guard<std::mutex> lock(mutex_);
    if (test_stream_accepting_ || test_stream_ingress_ || !test_stream_acks_.empty() || test_stream_completions_) return false;
    event = std::move(test_stream_event_);
    detached = std::move(test_stream_detached_);
  }
  (void)event; (void)detached; // Destroy callbacks only after releasing mutex_.
  return true;
}

void DesktopDevToolsSession::CompleteTestStreamCallback(std::function<void(bool)> callback, bool success) {
  try { if (callback) callback(success); } catch (...) {}
  std::lock_guard<std::mutex> lock(mutex_);
  --test_stream_completions_;
  test_stream_drained_.notify_all();
}

void DesktopDevToolsSession::ClearTestStream() {
  TestStreamEventSink event;
  TestStreamDetachSink detached;
  std::vector<std::function<void(bool)>> completions;
  {
    std::lock_guard<std::mutex> lock(mutex_);
    test_stream_accepting_ = false;
    detached = std::move(test_stream_detached_);
    event = std::move(test_stream_event_);
    for (auto& [_, completion] : test_stream_acks_) completions.push_back(std::move(completion));
    test_stream_acks_.clear();
    test_stream_completions_ += completions.size() + (detached ? 1 : 0);
    test_stream_drained_.notify_all();
  }
  (void)event; // Destroy the replaced event sink outside mutex_.
  for (auto& completion : completions) CompleteTestStreamCallback(std::move(completion), false);
  if (detached) CompleteTestStreamCallback([detached = std::move(detached)](bool) { detached(); }, false);
}

void DesktopDevToolsSession::SendTestStreamAck(CefRefPtr<CefBrowser> browser, int session_id,
                                               std::function<void(bool)> completed) {
  if (!completed) return;
  if (!browser || session_id <= 0 || !CefCurrentlyOn(TID_UI) || !browser->GetHost()) {
    completed(false); return;
  }
  int id = 0;
  {
    std::lock_guard<std::mutex> lock(mutex_);
    if (browser_ && browser_->IsSame(browser) && test_stream_event_ && test_stream_acks_.size() < 3) {
      id = next_message_id_++;
      test_stream_acks_.emplace(id, completed);
    }
  }
  if (!id) { completed(false); return; }
  const auto params = ToCefDictionary({{"sessionId", session_id}});
  if (!params || browser->GetHost()->ExecuteDevToolsMethod(id, "Page.screencastFrameAck", params) == 0) {
    std::function<void(bool)> failed;
    {
      std::lock_guard<std::mutex> lock(mutex_);
      const auto item = test_stream_acks_.find(id);
      if (item != test_stream_acks_.end()) {
        failed = std::move(item->second); test_stream_acks_.erase(item); ++test_stream_completions_;
      }
    }
    if (failed) CompleteTestStreamCallback(std::move(failed), false);
  }
}
#endif

}  // namespace kelpie
