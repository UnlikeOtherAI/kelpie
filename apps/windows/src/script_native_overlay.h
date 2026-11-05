#pragma once
#include <windows.h>
#include <functional>
#include <nlohmann/json.hpp>
#include "script_detached_marker_policy.h"
namespace kelpie::windows {
// Native layered presentation is scoped to renderer bounds and never sends page hover events.
class ScriptNativeOverlay {
 public:
  using DocumentGuard=std::function<bool(const nlohmann::json&)>;
  ScriptNativeOverlay(HWND viewport, HWND owner, DocumentGuard guard);
  ~ScriptNativeOverlay();
  void Show(const nlohmann::json& presentation, std::function<void()> stop, std::function<bool()> valid);
  bool RetireIfRevision(std::uint64_t revision);
 private:
  static LRESULT CALLBACK StopProc(HWND,UINT,WPARAM,LPARAM);
  void RetireDetached();
  HWND viewport_, owner_, canvas_ = nullptr, stop_window_ = nullptr, button_ = nullptr;
  std::function<void()> stop_;
  std::function<bool()> valid_;
  DocumentGuard guard_;
  DetachedMarkerAnchor anchor_;
  DetachedMarkerGeometry liveGeometry_;
  bool detachedAnchored_=false;
  nlohmann::json shown_=nlohmann::json::object();
  ULONGLONG shown_at_=0;
};
}
