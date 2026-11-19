#pragma once
#include <functional>
#include <string>

#include "../../../core/native/desktop-ui/address_load_progress.h"

#if KELPIE_LINUX_HAS_GTK
#include <gtk/gtk.h>
#else
typedef struct _GtkWidget GtkWidget;
#endif

namespace kelpie { struct TabSnapshot; }

namespace kelpie::linuxapp {

class LinuxApp;

class UrlBar {
 public:
  explicit UrlBar(LinuxApp& app);

  GtkWidget* widget() const;
  void Sync();
  void SyncLoadProgress(const TabSnapshot* tab);
  void Focus();
  std::function<void(int)> tool_action;

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
  AddressLoadProgress load_progress_;
  AddressLoadFrame load_frame_;
  std::string load_tab_;
  GtkWidget* account_button_ = nullptr;
  GtkWidget* inspector_3d_button_ = nullptr;
  unsigned long inspector_toggle_handler_ = 0;
  std::string avatar_;
#if KELPIE_LINUX_HAS_GTK
  GtkListStore* completion_ = nullptr;
#endif
};

}  // namespace kelpie::linuxapp
