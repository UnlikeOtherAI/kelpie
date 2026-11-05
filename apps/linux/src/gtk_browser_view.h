#pragma once
#include <string>

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
  std::string marker_anchor_;
  int marker_x_=0, marker_y_=0, marker_width_=0, marker_height_=0, marker_scale_=0;
  int marker_frame_width_=0, marker_frame_height_=0;
#if KELPIE_LINUX_HAS_GTK
  void ConnectKeyboard();
  GtkIMContext* input_ = nullptr;
  bool composing_ = false;
#endif
};

}  // namespace kelpie::linuxapp
