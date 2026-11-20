#pragma once

#if KELPIE_LINUX_HAS_GTK
#include <gtk/gtk.h>

#include "kelpie/desktop_engine.h"

namespace kelpie::linuxapp {

class GtkFileChooserPanel {
 public:
  explicit GtkFileChooserPanel(GtkWindow* window) : window_(window) {}
  ~GtkFileChooserPanel() { Cancel(); }

  void Open(const DesktopEngine::FileChooserRequest& request,
            DesktopEngine::FileChooserCompletion complete);
  void Cancel();

 private:
  void Complete(int response);

  GtkWindow* window_;
  GtkFileChooserNative* dialog_ = nullptr;
  DesktopEngine::FileChooserCompletion complete_;
};

}  // namespace kelpie::linuxapp
#endif
