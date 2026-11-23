#pragma once

#include <string>

#if KELPIE_LINUX_HAS_GTK
#include <gio/gio.h>
#include <gtk/gtk.h>

namespace kelpie::linuxapp {

// Confirms an app link (`slack:`, `mailto:`) with the person, then opens it
// with the app the desktop registered for its scheme. Nothing is shown when no
// app handles the scheme or another prompt is already open.
class GtkExternalAppPrompt {
 public:
  explicit GtkExternalAppPrompt(GtkWindow* window) : window_(window) {}
  ~GtkExternalAppPrompt() { Cancel(); }

  void Show(const std::string& requester, const std::string& url) {
    const auto colon = url.find(':');
    if (dialog_ || colon == std::string::npos || !gtk_widget_get_visible(GTK_WIDGET(window_))) return;
    GAppInfo* app = g_app_info_get_default_for_uri_scheme(url.substr(0, colon).c_str());
    if (!app) return;
    const std::string name = g_app_info_get_display_name(app);
    app_ = app;
    url_ = url;
    dialog_ = gtk_message_dialog_new(window_, GTK_DIALOG_MODAL, GTK_MESSAGE_QUESTION, GTK_BUTTONS_NONE,
                                     "Open “%s”?", name.c_str());
    gtk_message_dialog_format_secondary_text(GTK_MESSAGE_DIALOG(dialog_), "%s wants to open this app.",
                                             requester.empty() ? "This page" : requester.c_str());
    auto* dialog = GTK_DIALOG(dialog_);
    gtk_dialog_add_buttons(dialog, "Cancel", GTK_RESPONSE_CANCEL, ("Open " + name).c_str(), GTK_RESPONSE_ACCEPT, nullptr);
    gtk_dialog_set_default_response(dialog, GTK_RESPONSE_CANCEL);
    g_signal_connect(dialog, "response", G_CALLBACK(+[](GtkDialog*, int response, gpointer self) {
      static_cast<GtkExternalAppPrompt*>(self)->Complete(response == GTK_RESPONSE_ACCEPT);
    }), this);
    gtk_widget_show(dialog_);
  }

  void Cancel() { Complete(false); }

 private:
  void Complete(bool open) {
    if (!dialog_) return;
    auto* dialog = dialog_;
    dialog_ = nullptr;
    gtk_widget_destroy(dialog);
    GAppInfo* app = app_;
    app_ = nullptr;
    if (open && gtk_widget_get_visible(GTK_WIDGET(window_))) {
      // Launch the app the person agreed to, even if the default changed.
      GList* uris = g_list_append(nullptr, const_cast<char*>(url_.c_str()));
      g_app_info_launch_uris(app, uris, nullptr, nullptr);
      g_list_free(uris);
    }
    g_object_unref(app);
  }

  GtkWindow* window_;
  GtkWidget* dialog_ = nullptr;
  GAppInfo* app_ = nullptr;
  std::string url_;
};

}  // namespace kelpie::linuxapp
#endif
