#pragma once
#include "script_marker_anchor.h"

#if KELPIE_LINUX_HAS_GTK
#include <gtk/gtk.h>
#else
typedef struct _GtkWidget GtkWidget;
#endif

namespace kelpie::linuxapp {

class LinuxApp;

class GtkBrowserView {
 public:
  explicit GtkBrowserView(LinuxApp& app);

  GtkWidget* widget() const;
  void Sync();

 private:
  LinuxApp& app_;
  GtkWidget* frame_ = nullptr;
  GtkWidget* canvas_ = nullptr;
  GtkWidget* label_ = nullptr;
  GtkWidget* stop_ = nullptr;
  bool attached_ = false;
  ScriptMarkerAnchor marker_anchor_;
#if KELPIE_LINUX_HAS_GTK
  void ConnectKeyboard();
  GtkIMContext* input_ = nullptr;
  bool composing_ = false;
#endif
};

}  // namespace kelpie::linuxapp
