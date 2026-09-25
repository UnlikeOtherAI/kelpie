#include "window_geometry.h"
#include <nlohmann/json.hpp>
#include <algorithm>
#include <fstream>

namespace kelpie::linuxapp {
WindowGeometry::WindowGeometry(GtkWindow* window,const std::string& profile):path_(profile+"/window.json") {
#if KELPIE_LINUX_HAS_GTK
  gtk_window_get_default_size(window,&width_,&height_);
  std::ifstream input(path_);
  const auto saved=nlohmann::json::parse(input,nullptr,false);
  auto number=[&](const char* key,int fallback) {
    return saved.is_object()&&saved.contains(key)&&saved[key].is_number_integer()?saved[key].get<int>():fallback;
  };
  auto* monitor=gdk_display_get_primary_monitor(gdk_display_get_default());
  if(!monitor)monitor=gdk_display_get_monitor(gdk_display_get_default(),0);
  GdkRectangle area{0,0,1920,1080}; if(monitor)gdk_monitor_get_workarea(monitor,&area);
  width_=std::clamp(number("width",width_),640,std::max(640,area.width));
  height_=std::clamp(number("height",height_),400,std::max(400,area.height));
  gtk_window_set_default_size(window,width_,height_);
  if(saved.is_object()&&saved.contains("x")&&saved.contains("y")) {
    x_=std::clamp(number("x",area.x),area.x,area.x+std::max(0,area.width-width_));
    y_=std::clamp(number("y",area.y),area.y,area.y+std::max(0,area.height-height_));
    positioned_=true; gtk_window_move(window,x_,y_);
  }
  maximized_=saved.is_object()&&saved.contains("maximized")&&saved["maximized"].is_boolean()&&saved["maximized"].get<bool>();
  if(maximized_)gtk_window_maximize(window);
  g_signal_connect(window,"configure-event",G_CALLBACK(+[](GtkWidget* widget,GdkEventConfigure*,gpointer raw)->gboolean {
    auto* self=static_cast<WindowGeometry*>(raw);
    const auto state=gdk_window_get_state(gtk_widget_get_window(widget));
    if(!(state&(GDK_WINDOW_STATE_MAXIMIZED|GDK_WINDOW_STATE_FULLSCREEN|GDK_WINDOW_STATE_ICONIFIED))) {
      gtk_window_get_size(GTK_WINDOW(widget),&self->width_,&self->height_);
      gtk_window_get_position(GTK_WINDOW(widget),&self->x_,&self->y_); self->positioned_=true;
    }
    return FALSE;
  }),this);
  g_signal_connect(window,"window-state-event",G_CALLBACK(+[](GtkWidget*,GdkEventWindowState* event,gpointer raw)->gboolean {
    static_cast<WindowGeometry*>(raw)->maximized_=event->new_window_state&GDK_WINDOW_STATE_MAXIMIZED;return FALSE;
  }),this);
#else
  (void)window;
#endif
}
void WindowGeometry::Save() const {
#if KELPIE_LINUX_HAS_GTK
  nlohmann::json value{{"width",width_},{"height",height_},{"maximized",maximized_}};
  if(positioned_){value["x"]=x_;value["y"]=y_;}
  const auto data=value.dump();
  g_file_set_contents(path_.c_str(),data.c_str(),data.size(),nullptr);
#endif
}
}
