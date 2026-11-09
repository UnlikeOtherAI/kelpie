#pragma once

#include "release_feed.h"
#include <chrono>
#include <filesystem>
#include <fstream>
#include <functional>
#include <future>
#include <set>

namespace kelpie::updates {
// Used only by standalone hosts. Network work never runs in the browser/UI loop.
class ReleaseMonitor {
 public:
  using Clock = std::chrono::steady_clock;
  ReleaseMonitor(std::string target, std::string current, std::filesystem::path preferences,
      std::function<std::string()> fetch)
      : target_(std::move(target)), current_(std::move(current)),
        preferences_(std::move(preferences)), fetch_(std::move(fetch)) {
    std::ifstream input(preferences_);
    const auto saved = nlohmann::json::parse(input, nullptr, false);
    if (saved.is_array()) for (const auto& item : saved)
      if (item.is_string() && Version(item.get<std::string>())) skipped_.insert(item.get<std::string>());
  }

  std::optional<Release> Tick(Clock::time_point now = Clock::now()) {
    if (pending_.valid()) {
      if (pending_.wait_for(std::chrono::seconds(0)) != std::future_status::ready) return std::nullopt;
      try {
        auto body = pending_.get();
        if (!nlohmann::json::parse(body, nullptr, false).is_array()) throw std::runtime_error("Invalid feed");
        next_check_ = now + std::chrono::hours(6);
        const auto release = FindRelease(body, target_, current_);
        // Choose the newest before applying choices. Skipping it must not offer an older release.
        if (release && !skipped_.contains(release->version) && !dismissed_.contains(release->version)) {
          dismissed_.insert(release->version);
          return release;
        }
      } catch (...) { next_check_ = now + std::chrono::minutes(15); }
    } else if (now >= next_check_) {
      try { pending_ = std::async(std::launch::async, fetch_); }
      catch (...) { next_check_ = now + std::chrono::minutes(15); }
    }
    return std::nullopt;
  }

  bool Skip(const Release& release) {
    auto saved = skipped_;
    saved.insert(release.version);
    // The parent is owned/created by the app, never by an untrusted release.
    const auto temporary = std::filesystem::path(preferences_.string() + ".tmp");
    { std::ofstream output(temporary); output << nlohmann::json(saved).dump(); output.close();
      if (!output) return false; }
    std::error_code error;
    std::filesystem::rename(temporary, preferences_, error);
#ifdef _WIN32
    // Windows rename cannot replace an existing file. Keep the prior preference on failure.
    if (error) {
      if (!MoveFileExW(temporary.c_str(), preferences_.c_str(), MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH)) return false;
      error.clear();
    }
#endif
    if (error) return false;
    skipped_ = std::move(saved);
    return true;
  }

  void Retry(const Release& release) { dismissed_.erase(release.version); next_check_ = Clock::now(); }

 private:
  std::string target_, current_;
  std::filesystem::path preferences_;
  std::function<std::string()> fetch_;
  std::set<std::string> skipped_, dismissed_;
  Clock::time_point next_check_{};
  std::future<std::string> pending_;
};
}  // namespace kelpie::updates
