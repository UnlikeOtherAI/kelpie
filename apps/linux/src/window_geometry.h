#pragma once
#include "ui_theme.h"
#include <string>

namespace kelpie::linuxapp {
// GTK owns the signal connections; this value outlives the window.
class WindowGeometry {
 public:
  WindowGeometry(GtkWindow* window,const std::string& profile);
  void Save() const;
 private:
  std::string path_;
  int width_=1280,height_=800,x_=0,y_=0;
  bool positioned_=false,maximized_=false;
};
}
