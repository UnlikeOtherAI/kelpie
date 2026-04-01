#pragma once

#if MOLLOTOV_LINUX_HAS_GTK
#include <gtk/gtk.h>
#else
typedef struct _GtkWidget GtkWidget;
#endif

namespace mollotov::linuxapp {

class LinuxApp;

class UrlBar {
 public:
  explicit UrlBar(LinuxApp& app);

  GtkWidget* widget() const;
  void Sync();

 private:
  LinuxApp& app_;
  GtkWidget* root_ = nullptr;
  GtkWidget* back_button_ = nullptr;
  GtkWidget* forward_button_ = nullptr;
  GtkWidget* reload_button_ = nullptr;
  GtkWidget* brand_badge_ = nullptr;
  GtkWidget* entry_shell_ = nullptr;
  GtkWidget* entry_ = nullptr;
  bool editing_ = false;
};

}  // namespace mollotov::linuxapp
