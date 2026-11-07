#pragma once

#include <string>
#include <string_view>

namespace kelpie::windows {

enum class StartupStage {
  kProfileOwnership,
  kNativeHost,
  kCefBrowser,
  kAttachedBrowser,
  kHttpListener,
  kReadinessPublication,
  kReady,
};

class StartupDiagnostics {
 public:
  void Enter(StartupStage stage) {
    stage_ = stage;
    error_.clear();
  }

  void Fail(StartupStage stage, std::string error) {
    stage_ = stage;
    error_ = std::move(error);
    if (error_.size() > kMaximumErrorLength) error_.resize(kMaximumErrorLength);
  }

  void Ready() { Enter(StartupStage::kReady); }
  bool ready() const { return stage_ == StartupStage::kReady && error_.empty(); }
  StartupStage stage() const { return stage_; }
  const std::string& error() const { return error_; }

  std::wstring Presentation() const {
    if (ready()) return L"";
    std::wstring text = L"Browser startup failed during ";
    text += StageName(stage_);
    if (!error_.empty()) {
      text += L": ";
      text.append(error_.begin(), error_.end());
    }
    return text;
  }

 private:
  static constexpr std::size_t kMaximumErrorLength = 160;

  static std::wstring_view StageName(StartupStage stage) {
    switch (stage) {
      case StartupStage::kProfileOwnership: return L"profile ownership";
      case StartupStage::kNativeHost: return L"native host setup";
      case StartupStage::kCefBrowser: return L"Chromium browser setup";
      case StartupStage::kAttachedBrowser: return L"browser attachment";
      case StartupStage::kHttpListener: return L"local control listener";
      case StartupStage::kReadinessPublication: return L"control readiness publication";
      case StartupStage::kReady: return L"ready state";
    }
    return L"unknown stage";
  }

  StartupStage stage_ = StartupStage::kProfileOwnership;
  std::string error_;
};

}  // namespace kelpie::windows
