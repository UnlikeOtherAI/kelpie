#pragma once

#include <cstdint>
#include <functional>
#include <mutex>
#include <string>
#include <vector>

#include "kelpie/renderer_interface.h"

namespace kelpie {

class CefRenderer : public RendererInterface {
 public:
  struct Callbacks {
    std::function<std::string(const std::string&)> evaluate_js;
    std::function<std::vector<std::uint8_t>()> take_snapshot;
    std::function<void(const std::string&)> load_url;
    std::function<std::string()> current_url;
    std::function<std::string()> current_title;
    std::function<bool()> is_loading;
    std::function<bool()> can_go_back;
    std::function<bool()> can_go_forward;
    std::function<void()> go_back;
    std::function<void()> go_forward;
    std::function<void()> reload;
  };

  CefRenderer();
  explicit CefRenderer(Callbacks callbacks);

  void SetCallbacks(Callbacks callbacks);

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

 private:
  using StringCallback = std::function<std::string()>;
  using BoolCallback = std::function<bool()>;
  using VoidCallback = std::function<void()>;

  static std::string InvokeString(const StringCallback& callback);
  static bool InvokeBool(const BoolCallback& callback);
  static void InvokeVoid(const VoidCallback& callback);

  mutable std::mutex mutex_;
  Callbacks callbacks_;
};

}  // namespace kelpie
