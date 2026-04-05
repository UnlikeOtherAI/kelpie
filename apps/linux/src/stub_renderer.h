#pragma once

#include <mutex>
#include <string>
#include <vector>

#include "kelpie/renderer_interface.h"

namespace kelpie::linuxapp {

class StubRenderer final : public kelpie::RendererInterface {
 public:
  explicit StubRenderer(std::string initial_url);

  std::string EvaluateJs(const std::string& script) override;
  std::vector<std::uint8_t> TakeSnapshot() override;
  void LoadUrl(const std::string& url) override;
  std::string CurrentUrl() const override;
  std::string CurrentTitle() const override;
  bool IsLoading() const override;
  bool CanGoBack() const override;
  bool CanGoForward() const override;
  void GoBack() override;
  void GoForward() override;
  void Reload() override;

  bool SupportsScreenshots() const;

 private:
  static std::string TitleForUrl(const std::string& url);
  void NavigateInternal(const std::string& url, bool replace);
  void ApplyHistoryEntry();

  mutable std::mutex mutex_;
  std::vector<std::string> history_;
  std::size_t index_ = 0;
  std::string current_url_;
  std::string title_;
};

}  // namespace kelpie::linuxapp
