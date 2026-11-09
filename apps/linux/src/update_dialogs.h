#pragma once
#include <gtk/gtk.h>

namespace kelpie::linuxapp::updates_ui {
inline GtkWidget* Prompt(GtkWindow* owner, const char* version) {
  auto* dialog = gtk_message_dialog_new(owner, GTK_DIALOG_DESTROY_WITH_PARENT,
      GTK_MESSAGE_INFO, GTK_BUTTONS_NONE, "Kelpie %s is available", version);
  gtk_message_dialog_format_secondary_text(GTK_MESSAGE_DIALOG(dialog), "%s",
      "Update downloads, verifies and installs the new version, then restarts Kelpie. Not now asks again next time you start the app.");
  gtk_dialog_add_buttons(GTK_DIALOG(dialog), "Update", 100, "Skip version", 101, "Not now", 102, nullptr);
  gtk_dialog_set_default_response(GTK_DIALOG(dialog), 102);
  return dialog;
}
inline GtkWidget* Progress(GtkWindow* owner) {
  auto* dialog = gtk_message_dialog_new(owner, GTK_DIALOG_DESTROY_WITH_PARENT, GTK_MESSAGE_INFO, GTK_BUTTONS_NONE,
      "%s", "Downloading and verifying update… Kelpie will restart when ready.");
  gtk_window_set_deletable(GTK_WINDOW(dialog), FALSE);
  return dialog;
}
}
