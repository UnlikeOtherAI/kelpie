// The cookie sync adapter over the global CefCookieManager.
#include "kelpie/desktop_sync_cookie_store.h"

#include <cstdint>
#include <functional>
#include <mutex>

#include "include/cef_task.h"
#include "desktop_cookie_store.h"
#include "desktop_cookie_store_cef.h"
#include "kelpie/desktop_engine.h"

namespace kelpie {
namespace {

using Json = nlohmann::json;
constexpr std::int64_t kScanIntervalMs = 15000;

class FunctionTask final : public CefTask {
 public:
  explicit FunctionTask(std::function<void()> body) : body_(std::move(body)) {}
  void Execute() override { body_(); }

 private:
  std::function<void()> body_;
  IMPLEMENT_REFCOUNTING(FunctionTask);
};

// The listener and the generation that arms the 15 s timer chain. Firing
// holds the mutex, so a removed listener is never called after removal returns.
struct ListenerState {
  std::mutex mutex;
  std::function<void()> listener;
  std::uint64_t generation = 0;

  void Fire() {
    std::lock_guard lock(mutex);
    if (listener) listener();
  }
};

void ArmTimer(const std::shared_ptr<ListenerState>& state, std::uint64_t generation) {
  CefPostDelayedTask(TID_UI, new FunctionTask([state, generation] {
                       {
                         std::lock_guard lock(state->mutex);
                         if (state->generation != generation) return;  // removed or replaced
                         if (state->listener) state->listener();
                       }
                       ArmTimer(state, generation);
                     }),
                     kScanIntervalMs);
}

class DesktopSyncCookieStore final : public SyncCookieStore {
 public:
  explicit DesktopSyncCookieStore(DesktopEngine& engine)
      : engine_(engine), state_(std::make_shared<ListenerState>()) {
    engine_.SetDefaultStoreLoadSink([state = state_] { state->Fire(); });
  }

  ~DesktopSyncCookieStore() override {
    SetChangeListener(nullptr);
    engine_.SetDefaultStoreLoadSink(nullptr);
  }

  bool Snapshot(Json* cookies, Json* coverage, const Cancelled& cancelled) override {
    if (!engine_.is_initialized()) return false;
    CefCookieBackend backend(CefCookieManager::GetGlobalManager(nullptr));
    return desktop_cookie_store::SyncSnapshot(backend, cookies, coverage, cancelled);
  }

  Json Apply(const Json& ops, const Cancelled& cancelled) override {
    if (!engine_.is_initialized()) return Json::array();
    CefCookieBackend backend(CefCookieManager::GetGlobalManager(nullptr));
    // A short result makes core-sync abort the merge instead of committing a guess.
    auto results = desktop_cookie_store::ApplySyncOps(backend, ops, cancelled);
    return results ? *results : Json::array();
  }

  void SetChangeListener(std::function<void()> listener) override {
    const bool arm = static_cast<bool>(listener);
    std::uint64_t generation;
    {
      std::lock_guard lock(state_->mutex);
      state_->listener = std::move(listener);
      generation = ++state_->generation;
    }
    if (arm && engine_.is_initialized()) ArmTimer(state_, generation);
  }

 private:
  DesktopEngine& engine_;
  std::shared_ptr<ListenerState> state_;
};

}  // namespace

std::unique_ptr<SyncCookieStore> CreateSyncCookieStore(DesktopEngine& engine) {
  return std::make_unique<DesktopSyncCookieStore>(engine);
}

}  // namespace kelpie
