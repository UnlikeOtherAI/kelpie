#pragma once
#include <memory>
#if KELPIE_LINUX_HAS_GTK
#include <gtk/gtk.h>
#endif
namespace kelpie::linuxapp {
class LinuxApp;
class StandaloneUpdates {
 public:
#if KELPIE_LINUX_HAS_GTK
  StandaloneUpdates(LinuxApp& app, GtkWindow* window);
  ~StandaloneUpdates();
  void Tick();
 private:
  struct Impl;
  std::unique_ptr<Impl> impl_;
#endif
};
}
