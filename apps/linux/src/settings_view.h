#pragma once

#if KELPIE_LINUX_HAS_GTK
#include <gtk/gtk.h>
#else
typedef struct _GtkWidget GtkWidget;
typedef struct _GtkWindow GtkWindow;
#endif

namespace kelpie::linuxapp {

class LinuxApp;

class SettingsView {
 public:
  explicit SettingsView(LinuxApp& app);

  void Show(GtkWindow* parent);
  void Refresh();

 private:
  LinuxApp& app_;
  GtkWidget* dialog_ = nullptr;
  GtkWidget* content_ = nullptr;
};

}  // namespace kelpie::linuxapp
