#include "url_bar.h"

#include "linux_app.h"
#include "ui_theme.h"

#if KELPIE_LINUX_HAS_GTK
#include <gtk/gtk.h>
#endif

namespace kelpie::linuxapp {

UrlBar::UrlBar(LinuxApp& app) : app_(app) {
#if KELPIE_LINUX_HAS_GTK
  ui::InstallTheme();
  root_ = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 6);
  gtk_style_context_add_class(gtk_widget_get_style_context(root_), "kelpie-toolbar");

  back_button_ = ui::CreateSymbolButton("go-previous-symbolic", "Back");
  forward_button_ = ui::CreateSymbolButton("go-next-symbolic", "Forward");
  reload_button_ = ui::CreateSymbolButton("view-refresh-symbolic", "Reload");
  brand_badge_ = ui::CreateBrandBadge(ui::kFontAwesomeChrome, "Chromium");
  entry_shell_ = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 8);
  entry_ = gtk_entry_new();
  gtk_entry_set_placeholder_text(GTK_ENTRY(entry_), "Enter URL");
  gtk_widget_set_hexpand(entry_shell_, TRUE);
  gtk_style_context_add_class(gtk_widget_get_style_context(entry_shell_), "kelpie-url-shell");
  gtk_style_context_add_class(gtk_widget_get_style_context(entry_), "kelpie-url-entry");

  gtk_box_pack_start(GTK_BOX(root_), back_button_, FALSE, FALSE, 0);
  gtk_box_pack_start(GTK_BOX(root_), forward_button_, FALSE, FALSE, 0);
  gtk_box_pack_start(GTK_BOX(root_), reload_button_, FALSE, FALSE, 0);
  gtk_box_pack_start(GTK_BOX(entry_shell_), brand_badge_, FALSE, FALSE, 0);
  gtk_box_pack_start(GTK_BOX(entry_shell_), entry_, TRUE, TRUE, 0);
  gtk_box_pack_start(GTK_BOX(root_), entry_shell_, TRUE, TRUE, 0);

  g_signal_connect_swapped(back_button_, "clicked", G_CALLBACK(+[](LinuxApp* app_ptr) { app_ptr->GoBack(); }),
                           &app_);
  g_signal_connect_swapped(forward_button_, "clicked",
                           G_CALLBACK(+[](LinuxApp* app_ptr) { app_ptr->GoForward(); }), &app_);
  g_signal_connect_swapped(reload_button_, "clicked", G_CALLBACK(+[](LinuxApp* app_ptr) { app_ptr->Reload(); }),
                           &app_);
  g_signal_connect(entry_, "focus-in-event", G_CALLBACK(+[](GtkWidget*, GdkEventFocus*, gpointer user_data) {
                     auto* self = static_cast<UrlBar*>(user_data);
                     self->editing_ = true;
                     return FALSE;
                   }),
                   this);
  g_signal_connect(entry_, "focus-out-event", G_CALLBACK(+[](GtkWidget*, GdkEventFocus*, gpointer user_data) {
                     auto* self = static_cast<UrlBar*>(user_data);
                     self->editing_ = false;
                     self->Sync();
                     return FALSE;
                   }),
                   this);
  g_signal_connect(entry_, "activate", G_CALLBACK(+[](GtkEntry* entry, gpointer user_data) {
                     auto* self = static_cast<UrlBar*>(user_data);
                     self->editing_ = false;
                     auto* app_ptr = &self->app_;
                     app_ptr->Navigate(gtk_entry_get_text(entry));
                   }),
                   this);
  Sync();
#endif
}

GtkWidget* UrlBar::widget() const {
  return root_;
}

void UrlBar::Sync() {
#if KELPIE_LINUX_HAS_GTK
  if (entry_ == nullptr) {
    return;
  }
  if (!editing_) {
    gtk_entry_set_text(GTK_ENTRY(entry_), app_.CurrentUrl().c_str());
  }
  gtk_widget_set_sensitive(back_button_, app_.CanGoBack());
  gtk_widget_set_sensitive(forward_button_, app_.CanGoForward());
#endif
}

}  // namespace kelpie::linuxapp
