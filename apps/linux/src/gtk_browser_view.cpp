#include "gtk_browser_view.h"

#include "linux_app.h"

#if MOLLOTOV_LINUX_HAS_GTK
#include <cairo.h>
#include <gdk/gdkkeysyms.h>
#include <gtk/gtk.h>
#endif

namespace mollotov::linuxapp {

GtkBrowserView::GtkBrowserView(LinuxApp& app) : app_(app) {
#if MOLLOTOV_LINUX_HAS_GTK
  frame_ = gtk_overlay_new();
  canvas_ = gtk_drawing_area_new();
  label_ = gtk_label_new("");
  gtk_container_add(GTK_CONTAINER(frame_), canvas_);
  gtk_overlay_add_overlay(GTK_OVERLAY(frame_), label_);
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
                     const auto snapshot = self->app_.SnapshotBytes();
                     const int width = gtk_widget_get_allocated_width(widget);
                     const int height = gtk_widget_get_allocated_height(widget);
                     if (snapshot.empty() || width <= 0 || height <= 0) {
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
                     return FALSE;
                   }),
                   this);

  g_signal_connect(canvas_, "focus-out-event", G_CALLBACK(+[](GtkWidget*, GdkEventFocus*, gpointer user_data) -> gboolean {
                     auto* self = static_cast<GtkBrowserView*>(user_data);
                     self->app_.FocusBrowser(false);
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
#if MOLLOTOV_LINUX_HAS_GTK
  if (label_ == nullptr) {
    return;
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

}  // namespace mollotov::linuxapp
