#include "gtk_browser_view.h"

#include "linux_app.h"
#if KELPIE_LINUX_HAS_CEF
#include "script_frame_compositor.h"
#endif

#if KELPIE_LINUX_HAS_GTK
#include <cairo.h>
#include <gdk/gdkkeysyms.h>
#include <gtk/gtk.h>
#endif

namespace kelpie::linuxapp {
namespace {
#if KELPIE_LINUX_HAS_GTK && KELPIE_LINUX_HAS_CEF
void CompositeScriptFrame(LinuxApp& app, OffscreenFrame& frame, nlohmann::json shown) {
  ScriptFrame composed{frame.width, frame.height, frame.width * 4, 0, std::move(frame.pixels)};
  if (frame.tab_id != shown.value("tabId", std::string()) || frame.generation != shown.value("generation", std::uint64_t(0))) {
    shown.erase("marker"); shown.erase("pointer"); shown.erase("commentary");
  }
  try { DrawScriptOverlay(composed, shown); }
  catch (...) { app.StopScript(); }
  frame.pixels = std::move(composed.bgra);
}
#endif
}

GtkBrowserView::GtkBrowserView(LinuxApp& app) : app_(app) {
#if KELPIE_LINUX_HAS_GTK
  frame_ = gtk_overlay_new();
  canvas_ = gtk_drawing_area_new();
  label_ = gtk_label_new("");
  gtk_container_add(GTK_CONTAINER(frame_), canvas_);
  gtk_overlay_add_overlay(GTK_OVERLAY(frame_), label_);
  stop_ = gtk_button_new_with_label("Stop script");
  gtk_widget_set_no_show_all(stop_, TRUE);
  gtk_widget_set_halign(stop_, GTK_ALIGN_END); gtk_widget_set_valign(stop_, GTK_ALIGN_START);
  gtk_widget_set_margin_top(stop_, 8); gtk_widget_set_margin_end(stop_, 8);
  gtk_widget_set_tooltip_text(stop_, "Stop the running browser script");
  gtk_overlay_add_overlay(GTK_OVERLAY(frame_), stop_);
  g_signal_connect(stop_, "clicked", G_CALLBACK(+[](GtkButton*, gpointer raw) {
    static_cast<GtkBrowserView*>(raw)->app_.StopScript();
  }), this);
  gtk_widget_set_halign(label_, GTK_ALIGN_START);
  gtk_widget_set_valign(label_, GTK_ALIGN_START);
  gtk_widget_set_margin_top(label_, 12);
  gtk_widget_set_margin_start(label_, 12);
  gtk_widget_set_hexpand(frame_, TRUE);
  gtk_widget_set_vexpand(frame_, TRUE);
  gtk_widget_set_hexpand(canvas_, TRUE);
  gtk_widget_set_vexpand(canvas_, TRUE);
  gtk_widget_set_can_focus(canvas_, TRUE);
  gtk_widget_add_events(canvas_,
                        GDK_BUTTON_PRESS_MASK |
                            GDK_BUTTON_RELEASE_MASK |
                            GDK_POINTER_MOTION_MASK |
                            GDK_SCROLL_MASK |
                            GDK_ENTER_NOTIFY_MASK |
                            GDK_LEAVE_NOTIFY_MASK |
                            GDK_FOCUS_CHANGE_MASK);
  Sync();
  ConnectKeyboard();

  g_signal_connect(canvas_, "realize", G_CALLBACK(+[](GtkWidget* widget, gpointer user_data) {
                     auto* self = static_cast<GtkBrowserView*>(user_data);
                     const int width = gtk_widget_get_allocated_width(widget);
                     const int height = gtk_widget_get_allocated_height(widget);
                     self->attached_ = self->app_.AttachBrowserHost(0, width, height);
                     if (self->attached_) {
                       gtk_widget_hide(self->label_);
                     }
                     self->Sync();
                   }),
                   this);

  g_signal_connect(canvas_, "size-allocate", G_CALLBACK(+[](GtkWidget* widget,
                                                           GtkAllocation* allocation,
                                                           gpointer user_data) {
                     auto* self = static_cast<GtkBrowserView*>(user_data);
                     if (allocation == nullptr) {
                       return;
                     }
                     self->app_.ResizeBrowserHost(allocation->width, allocation->height);
                     if (self->app_.HasNativeBrowser()) {
                       gtk_widget_hide(self->label_);
                     }
                   }),
                   this);

  g_signal_connect(canvas_, "draw", G_CALLBACK(+[](GtkWidget* widget, cairo_t* cr, gpointer user_data) {
                     auto* self = static_cast<GtkBrowserView*>(user_data);
                     auto frame = self->app_.ViewFrame();
#if KELPIE_LINUX_HAS_CEF
                     auto* top = gtk_widget_get_toplevel(widget);
                     if (frame.valid() && GTK_IS_WINDOW(top) && gtk_window_is_active(GTK_WINDOW(top))) {
                       auto shown = self->app_.ScriptPresentation();
                       if (shown.contains("marker")) {
                         int x=0,y=0;
                         const bool origin=gtk_widget_translate_coordinates(widget,top,0,0,&x,&y);
                         const int width=gtk_widget_get_allocated_width(widget), height=gtk_widget_get_allocated_height(widget);
                         const int scale=gtk_widget_get_scale_factor(widget);
                         const auto& marker=shown.at("marker");
                         const bool valid_frame=frame.tab_id==shown.value("tabId",std::string()) &&
                             frame.generation==shown.value("generation",std::uint64_t{});
                         const auto identity=nlohmann::json::array({shown.value("runId",std::string()),shown.value("tabId",std::string()),
                           shown.value("generation",std::uint64_t{}),shown.value("documentVersion",std::string()),
                           marker.value("actionIndex",-1)}).dump();
                         const bool detached=shown.value("detachedMarker",false);
                         if (!detached && valid_frame && origin && width>0 && height>0 && scale>0) {
                           self->marker_anchor_=identity; self->marker_x_=x; self->marker_y_=y;
                           self->marker_width_=width; self->marker_height_=height; self->marker_scale_=scale;
                           self->marker_frame_width_=frame.width; self->marker_frame_height_=frame.height;
                         } else if (detached && (!valid_frame || !origin || self->marker_anchor_!=identity ||
                             self->marker_x_!=x || self->marker_y_!=y || self->marker_width_!=width ||
                             self->marker_height_!=height || self->marker_scale_!=scale ||
                             self->marker_frame_width_!=frame.width || self->marker_frame_height_!=frame.height)) {
                           self->app_.RetireDetachedScriptMarker(shown.value("_presentationRevision",std::uint64_t{}));
                           shown.erase("marker"); self->marker_anchor_.clear();
                         }
                       }
                       CompositeScriptFrame(self->app_, frame, std::move(shown));
                     }
#endif
                     const auto& snapshot = frame.pixels;
                     const int width = frame.width;
                     const int height = frame.height;
                     if (!frame.valid()) {
                       cairo_set_source_rgb(cr, 0.12, 0.12, 0.12);
                       cairo_paint(cr);
                       return FALSE;
                     }

                     const int stride = cairo_format_stride_for_width(CAIRO_FORMAT_ARGB32, width);
                     const std::size_t expected_size =
                         static_cast<std::size_t>(height) * static_cast<std::size_t>(stride);
                     if (snapshot.size() < expected_size) {
                       cairo_set_source_rgb(cr, 0.12, 0.12, 0.12);
                       cairo_paint(cr);
                       return FALSE;
                     }

                     cairo_surface_t* surface = cairo_image_surface_create_for_data(
                         const_cast<unsigned char*>(snapshot.data()),
                         CAIRO_FORMAT_ARGB32,
                         width,
                         height,
                         stride);
                     cairo_set_source_surface(cr, surface, 0, 0);
                     cairo_paint(cr);
                     cairo_surface_destroy(surface);
                     return FALSE;
                   }),
                   this);

  g_signal_connect(canvas_, "focus-in-event", G_CALLBACK(+[](GtkWidget*, GdkEventFocus*, gpointer user_data) -> gboolean {
                     auto* self = static_cast<GtkBrowserView*>(user_data);
                     self->app_.FocusBrowser(true);
                     gtk_im_context_focus_in(self->input_);
                     return FALSE;
                   }),
                   this);

  g_signal_connect(canvas_, "focus-out-event", G_CALLBACK(+[](GtkWidget*, GdkEventFocus*, gpointer user_data) -> gboolean {
                     auto* self = static_cast<GtkBrowserView*>(user_data);
                     self->app_.FocusBrowser(false);
                     gtk_im_context_focus_out(self->input_);
                     return FALSE;
                   }),
                   this);

  g_signal_connect(canvas_, "button-press-event", G_CALLBACK(+[](GtkWidget* widget,
                                                                 GdkEventButton* event,
                                                                 gpointer user_data) -> gboolean {
                     auto* self = static_cast<GtkBrowserView*>(user_data);
                     if (event == nullptr) {
                       return FALSE;
                     }
                     gtk_widget_grab_focus(widget);
                     self->app_.FocusBrowser(true);
                     self->app_.SendBrowserMouseMove(static_cast<int>(event->x),
                                                     static_cast<int>(event->y),
                                                     false);
                     self->app_.SendBrowserMouseClick(static_cast<int>(event->x),
                                                      static_cast<int>(event->y),
                                                      static_cast<int>(event->button),
                                                      false,
                                                      event->type == GDK_2BUTTON_PRESS ? 2 : 1);
                     return TRUE;
                   }),
                   this);

  g_signal_connect(canvas_, "button-release-event", G_CALLBACK(+[](GtkWidget*,
                                                                   GdkEventButton* event,
                                                                   gpointer user_data) -> gboolean {
                     auto* self = static_cast<GtkBrowserView*>(user_data);
                     if (event == nullptr) {
                       return FALSE;
                     }
                     self->app_.SendBrowserMouseMove(static_cast<int>(event->x),
                                                     static_cast<int>(event->y),
                                                     false);
                     self->app_.SendBrowserMouseClick(static_cast<int>(event->x),
                                                      static_cast<int>(event->y),
                                                      static_cast<int>(event->button),
                                                      true,
                                                      event->type == GDK_2BUTTON_PRESS ? 2 : 1);
                     return TRUE;
                   }),
                   this);

  g_signal_connect(canvas_, "motion-notify-event", G_CALLBACK(+[](GtkWidget*,
                                                                  GdkEventMotion* event,
                                                                  gpointer user_data) -> gboolean {
                     auto* self = static_cast<GtkBrowserView*>(user_data);
                     if (event == nullptr) {
                       return FALSE;
                     }
                     self->app_.SendBrowserMouseMove(
                         static_cast<int>(event->x), static_cast<int>(event->y), false);
                     return TRUE;
                   }),
                   this);

  g_signal_connect(canvas_, "leave-notify-event", G_CALLBACK(+[](GtkWidget*,
                                                                 GdkEventCrossing* event,
                                                                 gpointer user_data) -> gboolean {
                     auto* self = static_cast<GtkBrowserView*>(user_data);
                     if (event == nullptr) {
                       return FALSE;
                     }
                     self->app_.SendBrowserMouseMove(
                         static_cast<int>(event->x), static_cast<int>(event->y), true);
                     return TRUE;
                   }),
                   this);

  g_signal_connect(canvas_, "scroll-event", G_CALLBACK(+[](GtkWidget*,
                                                           GdkEventScroll* event,
                                                           gpointer user_data) -> gboolean {
                     auto* self = static_cast<GtkBrowserView*>(user_data);
                     if (event == nullptr) {
                       return FALSE;
                     }
                     int delta_y = 0;
                     if (event->direction == GDK_SCROLL_UP) {
                       delta_y = 120;
                     } else if (event->direction == GDK_SCROLL_DOWN) {
                       delta_y = -120;
                     }
                     self->app_.SendBrowserMouseWheel(
                         static_cast<int>(event->x), static_cast<int>(event->y), 0, delta_y);
                     return TRUE;
                   }),
                   this);
#endif
}

GtkWidget* GtkBrowserView::widget() const {
  return frame_;
}

void GtkBrowserView::Sync() {
#if KELPIE_LINUX_HAS_GTK
  if (label_ == nullptr) {
    return;
  }
  auto* top = gtk_widget_get_toplevel(frame_);
  const bool foreground = GTK_IS_WINDOW(top) && gtk_widget_get_visible(top) && gtk_window_is_active(GTK_WINDOW(top));
  const bool playing = app_.ScriptPresentation(foreground).value("playing", false);
  if (stop_) {
    if (playing) gtk_widget_show(stop_); else gtk_widget_hide(stop_);
  }
  if (app_.HasNativeBrowser()) {
    gtk_widget_hide(label_);
    if (canvas_ != nullptr) {
      gtk_widget_queue_draw(canvas_);
    }
    return;
  }
  const std::string text =
      "Browser host\nURL: " + app_.CurrentUrl() + "\nTitle: " + app_.CurrentTitle() +
      "\nScreenshots: " + std::string(app_.ScreenshotSupported() ? "enabled" : "unavailable without CEF");
  gtk_widget_show(label_);
  gtk_label_set_text(GTK_LABEL(label_), text.c_str());
#endif
}

}  // namespace kelpie::linuxapp
