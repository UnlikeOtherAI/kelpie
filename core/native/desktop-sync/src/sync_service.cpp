// DesktopCookieSync lifecycle: sign-in/out detection, epochs, discovery
// registration, warm-up, scan scheduling, session expiry and worker reaping.
#include "sync_service.h"

#include <algorithm>
#include <filesystem>

#include "protocol.h"

namespace kelpie {
namespace {

constexpr auto kTick = std::chrono::milliseconds(100);
constexpr auto kRetry = std::chrono::seconds(30);
constexpr auto kScanMaxDelay = std::chrono::seconds(5);

std::filesystem::path PathFromUtf8(const std::string& text) {
  return std::filesystem::path(std::u8string(text.begin(), text.end()));
}

std::string Utf8(const std::filesystem::path& path) {
  const auto text = path.u8string();
  return std::string(text.begin(), text.end());
}

bool SameIdentity(const account::AccountService::Identity& a, const account::AccountService::Identity& b) {
  return a.signed_in == b.signed_in && a.hosted == b.hosted && a.subject == b.subject && a.generation == b.generation;
}

}  // namespace

DesktopCookieSync::DesktopCookieSync(Config config) : impl_(std::make_unique<Impl>(std::move(config))) {}
DesktopCookieSync::~DesktopCookieSync() { impl_->Stop(); }
void DesktopCookieSync::Tick() { impl_->Tick(); }
void DesktopCookieSync::Stop() { impl_->Stop(); }
Json DesktopCookieSync::Status() const { return impl_->Status(); }

DesktopCookieSync::Impl::Impl(Config config) : config_(std::move(config)) {
  if (!config_.now_millis) {
    config_.now_millis = [] {
      return std::chrono::duration_cast<std::chrono::milliseconds>(
                 std::chrono::system_clock::now().time_since_epoch()).count();
    };
  }
  if (config_.cookies) {
    store_ = std::make_unique<desktop_sync::StoreHost>(
        config_.cookies, [this] { OnHeadChanged(); }, [this](const std::string& message) { Log(message); });
  }
  control_ = std::thread([this] { ControlLoop(); });
}

DesktopCookieSync::Impl::~Impl() { Stop(); }

void DesktopCookieSync::Impl::Log(const std::string& message) const {
  if (config_.log) config_.log(message);
}

std::int64_t DesktopCookieSync::Impl::Now() const { return config_.now_millis(); }

DesktopCookieSync::Impl::EpochRef DesktopCookieSync::Impl::CurrentEpoch() const {
  std::lock_guard lock(mu_);
  return epoch_;
}

bool DesktopCookieSync::Impl::Live(const EpochRef& epoch) const {
  return epoch && !epoch->cancelled && !stopping_ && config_.account &&
         config_.account->Generation() == epoch->account_generation;
}

desktop_sync::StoreHost::Cancelled DesktopCookieSync::Impl::CancelledFor(const EpochRef& epoch) const {
  return [this, epoch] { return !Live(epoch); };
}

void DesktopCookieSync::Impl::Wake() {
  {
    std::lock_guard lock(mu_);
    woken_ = true;
  }
  wake_.notify_all();
}

void DesktopCookieSync::Impl::Tick() {
  if (!config_.account) return;
  const auto identity = config_.account->CurrentIdentity();
  std::lock_guard lock(mu_);
  if (stopping_ || (desired_ && SameIdentity(*desired_, identity))) return;
  desired_ = identity;
  woken_ = true;
  wake_.notify_all();
}

void DesktopCookieSync::Impl::Stop() {
  {
    std::lock_guard lock(mu_);
    stopping_ = true;
    woken_ = true;
  }
  wake_.notify_all();
  changed_.notify_all();
  uoa_.WakeAll();
  if (control_.joinable() && control_.get_id() != std::this_thread::get_id()) control_.join();
}

void DesktopCookieSync::Impl::ControlLoop() {
  while (true) {
    std::optional<account::AccountService::Identity> desired;
    {
      std::unique_lock lock(mu_);
      wake_.wait_for(lock, kTick, [this] { return woken_ || stopping_; });
      woken_ = false;
      if (stopping_) break;
      desired = desired_;
    }
    if (desired) Reconcile(*desired);
    RunTimers();
  }
  StopEpoch();
  ReapWorkers();
}

void DesktopCookieSync::Impl::Fail(const std::string& reason, std::uint64_t generation) {
  Log("cookie-sync: unavailable: " + reason);
  std::lock_guard lock(mu_);
  reason_ = reason;
  retry_at_ = Clock::now() + kRetry;
  failed_generation_ = generation;
}

void DesktopCookieSync::Impl::Reconcile(const account::AccountService::Identity& identity) {
  const EpochRef epoch = CurrentEpoch();
  const bool runnable = identity.signed_in && !identity.hosted && config_.discovery && store_;
  if (!runnable) {
    if (epoch) StopEpoch();
    std::lock_guard lock(mu_);
    reason_ = identity.hosted ? "embedded" : !config_.discovery ? "mdns-unavailable"
                                           : !store_ ? "no-cef" : "";
    return;
  }
  if (epoch && epoch->subject == identity.subject && epoch->account_generation == identity.generation) return;
  if (epoch) StopEpoch();
  {
    std::lock_guard lock(mu_);
    if (failed_generation_ == identity.generation && Clock::now() < retry_at_) return;
  }
  StartEpoch(identity);
}

std::map<std::string, std::string> DesktopCookieSync::Impl::Txt(const EpochRef& epoch, std::int64_t now) const {
  return {{"v", "1"}, {"id", epoch->replica}, {"h", sync::AccountHint(epoch->subject, now)}};
}

void DesktopCookieSync::Impl::StartEpoch(const account::AccountService::Identity& identity) {
  auto epoch = std::make_shared<Epoch>();
  epoch->subject = identity.subject;
  epoch->account_generation = identity.generation;
  epoch->replica = desktop_sync::RandomToken(16);  // fresh per open, never persisted
  epoch->launch = !opened_once_;                    // the first open in this process only
  epoch->opened = Clock::now();
  const std::string path = Utf8(PathFromUtf8(config_.profile_dir) / "sync" / "cookie-sync.json");
  std::string error;
  if (!store_->Open(path, {identity.subject, epoch->replica, epoch->launch, Now()}, &error)) {
    Fail("store-unavailable", identity.generation);
    return;
  }
  opened_once_ = true;
  // A device that cannot listen still syncs by connecting out to its peers.
  auto listener = std::make_unique<desktop_sync::SyncListener>(this);
  int port = 0;
  if (listener->Start(config_.bind_address)) {
    port = listener->port();
    listener_ = std::move(listener);
  } else {
    Log("cookie-sync: listener unavailable; connecting out only");
  }
  {
    std::lock_guard lock(mu_);
    epoch->id = ++epoch_counter_;
    epoch_ = epoch;
    warm_done_ = !epoch->launch;
    reason_.clear();
    failed_generation_.reset();
    port_ = port;
    peers_.clear();
    hint_date_ = sync::UtcDate(Now());
    if (!epoch->launch) scan_due_ = Clock::now();
  }
  const std::uint64_t id = epoch->id;
  if ((port > 0 && !config_.discovery->Advertise(port, Txt(epoch, Now()))) ||
      !config_.discovery->Browse([this, id](const SyncPeerAdvert& advert) { OnFound(id, advert); },
                                 [this, id](const std::string& instance) { OnLost(id, instance); })) {
    StopEpoch();
    Fail("mdns-unavailable", identity.generation);
    return;
  }
  config_.cookies->SetChangeListener([this] { OnCookiesChanged(); });
  Log(epoch->launch ? "cookie-sync: started (launch, warming)" : "cookie-sync: started");
}

void DesktopCookieSync::Impl::StopEpoch() {
  EpochRef epoch;
  std::vector<std::shared_ptr<Outgoing>> outgoing;
  std::vector<std::shared_ptr<Worker>> workers;
  std::vector<std::shared_ptr<desktop_sync::AbortSet>> aborts;
  {
    std::lock_guard lock(mu_);
    epoch = std::exchange(epoch_, nullptr);
    if (!epoch) return;
    epoch->cancelled = true;
    for (auto& [replica, peer] : peers_) {
      if (peer.outgoing) outgoing.push_back(peer.outgoing);
    }
    peers_.clear();
    incoming_.clear();
    pending_.clear();
    workers.swap(workers_);
    aborts.swap(handshake_aborts_);
    scan_due_.reset();
    scan_first_signal_.reset();
    port_ = 0;
    ++change_counter_;
  }
  changed_.notify_all();
  uoa_.WakeAll();
  config_.discovery->StopBrowsing();
  config_.discovery->StopAdvertising();  // also when nothing was advertised
  config_.cookies->SetChangeListener(nullptr);
  for (auto& abort : aborts) abort->AbortAll();
  for (auto& session : outgoing) session->aborts.AbortAll();
  for (auto& worker : workers) if (worker->thread.joinable()) worker->thread.join();
  for (auto& session : outgoing) {
    for (auto& worker : session->workers) if (worker->thread.joinable()) worker->thread.join();
  }
  if (listener_) {
    listener_->Stop();
    listener_.reset();
  }
  store_->Close();
  Log("cookie-sync: stopped");
}

void DesktopCookieSync::Impl::Spawn(std::vector<std::shared_ptr<Worker>>* owner, std::function<void()> body) {
  std::lock_guard lock(mu_);
  SpawnLocked(owner, std::move(body));
}

void DesktopCookieSync::Impl::SpawnLocked(std::vector<std::shared_ptr<Worker>>* owner, std::function<void()> body) {
  auto worker = std::make_shared<Worker>();
  worker->thread = std::thread([worker, body = std::move(body)] {
    body();
    worker->done = true;
  });
  owner->push_back(worker);
}

void DesktopCookieSync::Impl::ReapWorkers() {
  std::vector<std::shared_ptr<Worker>> finished;
  {
    std::lock_guard lock(mu_);
    const bool all = stopping_ && !epoch_;
    auto split = std::stable_partition(workers_.begin(), workers_.end(),
                                       [all](const auto& worker) { return !all && !worker->done; });
    finished.assign(split, workers_.end());
    workers_.erase(split, workers_.end());
  }
  for (auto& worker : finished) if (worker->thread.joinable()) worker->thread.join();
}

void DesktopCookieSync::Impl::RunTimers() {
  const EpochRef epoch = CurrentEpoch();
  if (!Live(epoch)) return;
  CheckWarmup(epoch);
  RefreshAdvertisement(epoch);
  bool scan = false;
  {
    std::lock_guard lock(mu_);
    if (scan_due_ && Clock::now() >= *scan_due_) {
      scan_due_.reset();
      scan_first_signal_.reset();
      scan = true;
    }
  }
  if (scan) store_->PostScan(Now(), CancelledFor(epoch));
  ExpireSessions();
  ScheduleHandshakes(epoch);
  ReapWorkers();
}

void DesktopCookieSync::Impl::CheckWarmup(const EpochRef& epoch) {
  const auto elapsed = Clock::now() - epoch->opened;
  {
    std::lock_guard lock(mu_);
    if (warm_done_) return;
    // Ends after a complete pull from every peer seen in the first window, or at the limit.
    bool finish = elapsed >= config_.timings.warmup_limit;
    if (!finish && elapsed >= config_.timings.warmup_window) {
      finish = std::all_of(peers_.begin(), peers_.end(), [](const auto& item) {
        return !item.second.in_warmup_window || item.second.warm_complete;
      });
    }
    if (!finish) return;
  }
  store_->FinishWarmup();
  {
    std::lock_guard lock(mu_);
    warm_done_ = true;
    scan_due_ = Clock::now();
  }
  Log("cookie-sync: warm-up finished");
}

void DesktopCookieSync::Impl::RefreshAdvertisement(const EpochRef& epoch) {
  const std::int64_t now = Now();
  const std::string today = sync::UtcDate(now);
  {
    std::lock_guard lock(mu_);
    if (today == hint_date_) return;
    hint_date_ = today;
  }
  if (CurrentPort() > 0) config_.discovery->UpdateTxt(Txt(epoch, now));
}

int DesktopCookieSync::Impl::CurrentPort() const {
  std::lock_guard lock(mu_);
  return port_;
}

void DesktopCookieSync::Impl::OnCookiesChanged() {
  std::lock_guard lock(mu_);
  if (!epoch_) return;
  const auto now = Clock::now();
  if (!scan_first_signal_) scan_first_signal_ = now;
  // A scan after quiet, but never starved by a page that keeps loading.
  scan_due_ = std::min(now + config_.timings.scan_quiet, *scan_first_signal_ + kScanMaxDelay);
}

void DesktopCookieSync::Impl::OnHeadChanged() {
  {
    std::lock_guard lock(mu_);
    ++change_counter_;
  }
  changed_.notify_all();
}

void DesktopCookieSync::Impl::ExpireSessions() {
  std::vector<std::shared_ptr<Outgoing>> ended;
  {
    std::lock_guard lock(mu_);
    const auto now = Clock::now();
    for (auto it = incoming_.begin(); it != incoming_.end();) {
      if (now < it->second->expires && it->second->epoch == epoch_) { ++it; continue; }
      const auto peer = peers_.find(it->second->peer_replica);
      if (peer != peers_.end() && peer->second.incoming == it->first) peer->second.incoming.clear();
      it = incoming_.erase(it);
    }
    pending_.erase(std::remove_if(pending_.begin(), pending_.end(),
                                  [now](const auto& item) { return now >= item->expires; }),
                   pending_.end());
    for (auto& [replica, peer] : peers_) {
      if (!peer.outgoing || !peer.outgoing->ended) continue;
      ended.push_back(peer.outgoing);
      const std::string error = peer.outgoing->end_error;
      peer.outgoing.reset();
      // Expiry and a responder that forgot the session handshake again at once;
      // a session superseded by the designated initiator's needs nothing.
      if (error.empty() || error == "SYNC_SESSION" || error == "SUPERSEDED") {
        peer.next_attempt = now;
      } else {
        Backoff(&peer, error);
      }
    }
  }
  for (auto& session : ended) {
    for (auto& worker : session->workers) if (worker->thread.joinable()) worker->thread.join();
  }
}

}  // namespace kelpie
