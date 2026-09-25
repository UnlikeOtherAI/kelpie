#include "ui_theme.h"
#include <cmath>
#include <string_view>

#if KELPIE_LINUX_HAS_GTK
namespace kelpie::linuxapp::ui {
GtkWidget* CreateChromeIcon(const char* name) {
  auto* view=gtk_drawing_area_new();
  gtk_widget_set_size_request(view,22,22);
  gtk_widget_set_halign(view,GTK_ALIGN_CENTER);
  gtk_widget_set_valign(view,GTK_ALIGN_CENTER);
  g_object_set_data_full(G_OBJECT(view),"icon",g_strdup(name),g_free);
  g_signal_connect(view,"draw",G_CALLBACK((+[](GtkWidget* widget,cairo_t* cr,gpointer)->gboolean {
    const std::string_view icon=static_cast<const char*>(g_object_get_data(G_OBJECT(widget),"icon"));
    GdkRGBA ink; gtk_style_context_get_color(gtk_widget_get_style_context(widget),gtk_widget_get_state_flags(widget),&ink);
    gdk_cairo_set_source_rgba(cr,&ink);
    cairo_translate(cr,(gtk_widget_get_allocated_width(widget)-24)/2.0,(gtk_widget_get_allocated_height(widget)-24)/2.0);
    cairo_set_line_width(cr,1.65); cairo_set_line_cap(cr,CAIRO_LINE_CAP_ROUND); cairo_set_line_join(cr,CAIRO_LINE_JOIN_ROUND);
    auto line=[&](double x,double y,double a,double b){cairo_move_to(cr,x,y);cairo_line_to(cr,a,b);};
    auto circle=[&](double x,double y,double r){cairo_new_sub_path(cr);cairo_arc(cr,x,y,r,0,6.283185307);};
    if(icon=="go-previous-symbolic"||icon=="go-next-symbolic") {
      if(icon=="go-next-symbolic"){cairo_translate(cr,24,0);cairo_scale(cr,-1,1);}
      line(21,12,3,12);line(3,12,11,4);line(3,12,11,20);
    } else if(icon=="view-refresh-symbolic") {
      cairo_arc(cr,12,12,8,.1,5.5);line(18,3,18,8);line(18,8,23,8);
    } else if(icon=="go-home-symbolic") {
      cairo_move_to(cr,3,10);cairo_line_to(cr,12,3);cairo_line_to(cr,21,10);cairo_line_to(cr,21,21);
      cairo_line_to(cr,15,21);cairo_line_to(cr,15,13);cairo_line_to(cr,9,13);cairo_line_to(cr,9,21);cairo_line_to(cr,3,21);cairo_close_path(cr);
    } else if(icon=="non-starred-symbolic") {
      for(int i=0;i<10;++i){double a=-1.570796327+i*.628318531;double r=i%2?4.5:10;
        if(i)cairo_line_to(cr,12+std::cos(a)*r,12+std::sin(a)*r);else cairo_move_to(cr,12+std::cos(a)*r,12+std::sin(a)*r);}
      cairo_close_path(cr);
    } else if(icon=="view-grid-symbolic") {
      for(int y:{4,15})for(int x:{4,15})cairo_rectangle(cr,x,y,5,5);
    } else if(icon=="document-open-recent-symbolic") {
      circle(12,12,9);line(12,6,12,12);line(12,12,17,14);
    } else if(icon=="network-workgroup-symbolic") {
      line(12,3,12,15);line(12,15,7,10);line(12,15,17,10);line(3,17,3,21);line(3,21,21,21);line(21,21,21,17);
    } else if(icon=="avatar-default-symbolic") {
      circle(12,12,10);circle(12,9,3);cairo_new_sub_path(cr);cairo_arc(cr,12,20,6,3.4,6.02);
    } else if(icon=="view-more-symbolic") {
      for(int y:{5,12,19})circle(12,y,1);cairo_fill(cr);
    } else if(icon=="window-close-symbolic") {
      line(7,7,17,17);line(17,7,7,17);
    } else if(icon=="window-minimize-symbolic") {
      line(7,12,17,12);
    } else if(icon=="window-maximize-symbolic") {
      cairo_rectangle(cr,7,7,10,10);
    } else if(icon=="list-add-symbolic") {
      line(5,12,19,12);line(12,5,12,19);
    } else {
      cairo_rectangle(cr,6,10,12,11);cairo_new_sub_path(cr);cairo_arc(cr,12,10,4,3.141592654,6.283185307);
    }
    cairo_stroke(cr);return TRUE;
  })),nullptr);
  return view;
}
} // namespace kelpie::linuxapp::ui
#endif
