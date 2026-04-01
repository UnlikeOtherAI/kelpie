#pragma once

#include <functional>
#include <memory>
#include <string>
#include <vector>

#include <nlohmann/json.hpp>

#include "mollotov/cef_renderer.h"

namespace mollotov {

class DesktopEngine {
 public:
  enum class Mode {
    kWindowed = 0,
    kOffscreen,
  };

  struct Size {
    int width = 1280;
    int height = 720;
  };

  struct Config {
    Mode mode = Mode::kOffscreen;
    Size viewport;
    int argc = 0;
    char** argv = nullptr;
    std::string initial_url;
    std::string cache_path;
    std::string user_agent;
    std::string browser_subprocess_path;
    std::string resources_dir_path;
    std::string locales_dir_path;
    bool external_message_pump = true;
    std::function<void(void*)> configure_window_info;
  };

  struct ViewportState {
    int width = 1280;
    int height = 720;
    double device_pixel_ratio = 1.0;
    bool offscreen = true;
  };

  using JsonEventSink = std::function<void(const nlohmann::json&)>;
  using NavigationSink = std::function<void(const std::string&, const std::string&)>;

  DesktopEngine();
  ~DesktopEngine();

  bool Initialize(const Config& config);
  void Shutdown();
  void DoMessageLoopWork();

  bool is_initialized() const;
  bool is_offscreen() const;

  ViewportState viewport() const;
  bool ResizeViewport(int width, int height);
  bool SendFocusEvent(bool focused);
  bool SendMouseMoveEvent(int x, int y, bool mouse_leave);
  bool SendMouseClickEvent(int x, int y, int button, bool mouse_up, int click_count);
  bool SendMouseWheelEvent(int x, int y, int delta_x, int delta_y);

  void SetConsoleSink(JsonEventSink sink);
  void SetNetworkSink(JsonEventSink sink);
  void SetNavigationSink(NavigationSink sink);

  CefRenderer& renderer();
  const CefRenderer& renderer() const;

  class Impl;

 private:
  std::unique_ptr<CefRenderer> renderer_;
  std::unique_ptr<Impl> impl_;
};

}  // namespace mollotov
