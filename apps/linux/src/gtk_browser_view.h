#pragma once

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
  bool attached_ = false;
};

}  // namespace kelpie::linuxapp
