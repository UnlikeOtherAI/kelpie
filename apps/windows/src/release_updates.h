#pragma once
#include "windows_app.h"
#include <memory>

namespace kelpie::windows {
class StandaloneUpdates {
 public:
  StandaloneUpdates(WindowsApp& app, std::wstring restart_arguments);
  ~StandaloneUpdates();
  void Tick();
 private:
  struct Impl;
  std::unique_ptr<Impl> impl_;
};
}
