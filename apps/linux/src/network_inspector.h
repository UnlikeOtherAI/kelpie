#pragma once

#if KELPIE_LINUX_HAS_GTK
#include <gtk/gtk.h>
#else
typedef struct _GtkWidget GtkWidget;
typedef struct _GtkComboBoxText GtkComboBoxText;
typedef struct _GtkListStore GtkListStore;
#endif

namespace kelpie::linuxapp {

class LinuxApp;

class NetworkInspector {
 public:
  explicit NetworkInspector(LinuxApp& app);

  GtkWidget* widget() const;
  void Refresh();

 private:
  LinuxApp& app_;
  GtkWidget* root_ = nullptr;
  GtkComboBoxText* method_filter_ = nullptr;
  GtkComboBoxText* type_filter_ = nullptr;
  GtkComboBoxText* source_filter_ = nullptr;
  GtkListStore* store_ = nullptr;
};

}  // namespace kelpie::linuxapp
