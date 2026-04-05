#pragma once

#if KELPIE_LINUX_HAS_GTK
#include <gtk/gtk.h>
#else
typedef struct _GtkWidget GtkWidget;
#endif

#include <string>

namespace kelpie::linuxapp {

class ToastView {
 public:
  ToastView();

  GtkWidget* widget() const;
  void Show(const std::string& message);

 private:
  GtkWidget* revealer_ = nullptr;
  GtkWidget* label_ = nullptr;
};

}  // namespace kelpie::linuxapp
