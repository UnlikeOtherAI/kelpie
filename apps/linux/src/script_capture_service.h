#pragma once
#include "kelpie/desktop_app.h"
#include "script_artifact_store.h"
#include <chrono>
#include <functional>
#include <memory>
#include <mutex>

namespace kelpie::linuxapp {
class LinuxScriptService : public std::enable_shared_from_this<LinuxScriptService> {
 public:
  using Json = nlohmann::json;
  using DocumentGuard = std::function<bool(const Json&)>;
  explicit LinuxScriptService(DocumentGuard guard);
  void Configure(DesktopApp::Config& config);
  Json Presentation(bool foreground) const;
  void Stop();
  ScriptArtifactStore& artifacts() { return artifacts_; }
 private:
  void Show(const Json& presentation, std::function<void()> stop, std::function<bool()> valid);
  std::uint64_t last_presentation_revision_=0;
  DocumentGuard guard_;
  ScriptArtifactStore artifacts_;
  mutable std::mutex mutex_;
  mutable Json presentation_ = Json::object();
  std::function<void()> stop_;
  mutable std::function<bool()> valid_;
  std::chrono::steady_clock::time_point shown_at_{};
};
}
