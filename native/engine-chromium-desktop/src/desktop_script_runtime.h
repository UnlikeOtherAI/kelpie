#pragma once
#include "kelpie/desktop_script_handler.h"
#include "kelpie/desktop_engine.h"
#include "kelpie/desktop_router.h"
#include <chrono>
#include <condition_variable>
#include <mutex>
#include <thread>

namespace kelpie {
class DesktopScriptHandler::Impl {
 public:
  using Json = nlohmann::json;
  using Clock = std::chrono::steady_clock;
  DesktopEngine& engine;
  DesktopRouter& router;
  Config config;
  mutable std::mutex mutex;
  std::condition_variable changed;
  bool running = false, sampler_ready = false, sampler_done = false, requested_step_png = false, presentation_latched=false;
  std::thread::id run_thread;
  std::shared_ptr<std::atomic<bool>> abort = std::make_shared<std::atomic<bool>>(false);
  std::atomic<bool> stop_sampler{false}, privacy_discard{false};
  mutable std::atomic<bool> grant_revoked{false};
  std::string owner, run_id, target_key, capture_error;
  Json status = {{"playing", false}}, terminal, presentation = Json::object(), artifacts = Json::array();
  Clock::time_point began, deadline;
  int action_index = -1, requested_step = -1, completed_step = -1;
  std::string requested_step_document;
  std::uint64_t requested_ticket=0, completed_ticket=0;
  Impl(DesktopEngine& e, DesktopRouter& r, Config c) : engine(e), router(r), config(std::move(c)) {}
  Json Play(const Json& body);
  Json Status(const Json& body);
  Json Abort(const Json& body);
  bool Authorized(const Json& body) const;
  bool Cancelled() const;
  void Pause(int milliseconds);
  Json Target(TabLease lease, const Json& target, const std::string& token = "", bool observe = false, bool refuse_sensitive = false);
  Json Perform(TabLease lease, const Json& action, const Json& script, const Json& typing_plan, Json* outputs, std::vector<std::string>* redactions);
  void Sample(TabLease lease, Json options);
  void StepScreenshot(int index, bool png, const std::string& document = "");
  double Elapsed() const;
  void Present();
};
std::string NewDesktopScriptId();
}
