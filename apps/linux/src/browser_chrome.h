#pragma once
#include "linux_app.h"
#if KELPIE_LINUX_HAS_GTK
#include <gtk/gtk.h>
#include <array>

namespace kelpie::linuxapp {
class BrowserChrome {
 public:
  BrowserChrome(LinuxApp& app,GtkWindow* window);
  ~BrowserChrome();
  GtkWidget* title() const { return title_; }
  GtkWidget* favorites() const { return favorites_; }
  GtkWidget* separator() const { return separator_; }
  void Sync();
  void AccountMenu(GtkWidget* anchor);
 private:
  LinuxApp& app_;
  GtkWindow* window_;
  GtkWidget *title_,*tabs_,*favorites_,*separator_;
  GtkCssProvider* css_;
  std::string tabs_key_,favorites_key_;
  std::array<double,3> color_{255,255,255},from_=color_,target_=color_;
  gint64 transition_=0,last_sample_=0;
  void Tabs();
  void Favorites();
  void Palette();
};
}  // namespace kelpie::linuxapp
#endif
