#pragma once

#include "kelpie/desktop_engine.h"

#if KELPIE_LINUX_HAS_GTK
#include <gtk/gtk.h>

namespace kelpie::linuxapp {

class GtkMicrophonePrompt {
 public:
  explicit GtkMicrophonePrompt(GtkWindow* window) : window_(window) {}
  ~GtkMicrophonePrompt() { Cancel(); }

  void Show(const std::string& origin, DesktopEngine::MicrophoneDecision decide) {
    if (dialog_ || !gtk_widget_get_visible(GTK_WIDGET(window_))) {
      decide(false);
      return;
    }
    dialog_ = gtk_message_dialog_new(window_, GTK_DIALOG_MODAL, GTK_MESSAGE_QUESTION,
                                     GTK_BUTTONS_NONE, "Allow microphone access?");
    gtk_message_dialog_format_secondary_text(GTK_MESSAGE_DIALOG(dialog_),
                                            "%s wants to use your microphone.", origin.c_str());
    auto* dialog = GTK_DIALOG(dialog_);
    gtk_dialog_add_buttons(dialog, "Deny", GTK_RESPONSE_NO, "Allow", GTK_RESPONSE_YES, nullptr);
    gtk_dialog_set_default_response(dialog, GTK_RESPONSE_NO);
    decide_ = std::move(decide);
    g_signal_connect(dialog, "response", G_CALLBACK(+[](GtkDialog*, int response, gpointer self) {
      static_cast<GtkMicrophonePrompt*>(self)->Complete(response == GTK_RESPONSE_YES);
    }), this);
    gtk_widget_show(dialog_);
  }

  void Cancel() { Complete(false); }

 private:
  void Complete(bool allowed) {
    if (!dialog_) return;
    auto* dialog = dialog_;
    dialog_ = nullptr;
    auto decide = std::move(decide_);
    gtk_widget_destroy(dialog);
    decide(allowed);
  }

  GtkWindow* window_;
  GtkWidget* dialog_ = nullptr;
  DesktopEngine::MicrophoneDecision decide_;
};

}  // namespace kelpie::linuxapp
#endif
