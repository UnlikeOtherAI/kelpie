#include "settings_view.h"

#include "linux_app.h"

#if MOLLOTOV_LINUX_HAS_GTK
#include <gtk/gtk.h>
#endif

namespace mollotov::linuxapp {

SettingsView::SettingsView(LinuxApp& app) : app_(app) {}

void SettingsView::Show(GtkWindow* parent) {
#if MOLLOTOV_LINUX_HAS_GTK
  if (dialog_ == nullptr) {
    dialog_ = gtk_dialog_new_with_buttons("Settings",
                                          parent,
                                          static_cast<GtkDialogFlags>(GTK_DIALOG_MODAL | GTK_DIALOG_DESTROY_WITH_PARENT),
                                          "_Close",
                                          GTK_RESPONSE_CLOSE,
                                          nullptr);
    content_ = gtk_box_new(GTK_ORIENTATION_VERTICAL, 8);
    gtk_widget_set_hexpand(content_, TRUE);
    gtk_widget_set_vexpand(content_, TRUE);
    gtk_window_set_default_size(GTK_WINDOW(dialog_), 560, 420);
    gtk_window_set_resizable(GTK_WINDOW(dialog_), TRUE);
    gtk_container_add(GTK_CONTAINER(gtk_dialog_get_content_area(GTK_DIALOG(dialog_))), content_);
    g_signal_connect_swapped(dialog_, "response", G_CALLBACK(gtk_widget_hide), dialog_);
  }
  Refresh();
  gtk_widget_show_all(dialog_);
#else
  (void)parent;
#endif
}

void SettingsView::Refresh() {
#if MOLLOTOV_LINUX_HAS_GTK
  if (content_ == nullptr) {
    return;
  }
  GList* children = gtk_container_get_children(GTK_CONTAINER(content_));
  for (GList* item = children; item != nullptr; item = item->next) {
    gtk_widget_destroy(GTK_WIDGET(item->data));
  }
  g_list_free(children);

  const auto info = app_.DeviceInfo();
  const std::string summary =
      "Port: " + std::to_string(app_.port()) + "\nProfile: " + app_.config().profile_dir +
      "\nURL: " + app_.CurrentUrl() + "\nName: " + info["device"]["name"].get<std::string>() +
      "\nModel: " + info["device"]["model"].get<std::string>() +
      "\nmDNS: " + app_.MdnsStatusText();
  gtk_box_pack_start(GTK_BOX(content_), gtk_label_new(summary.c_str()), FALSE, FALSE, 0);
#endif
}

}  // namespace mollotov::linuxapp
