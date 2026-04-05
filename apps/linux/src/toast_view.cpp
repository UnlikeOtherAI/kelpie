#include "toast_view.h"

#if KELPIE_LINUX_HAS_GTK
#include <gtk/gtk.h>
#endif

namespace kelpie::linuxapp {

ToastView::ToastView() {
#if KELPIE_LINUX_HAS_GTK
  revealer_ = gtk_revealer_new();
  gtk_widget_set_halign(revealer_, GTK_ALIGN_CENTER);
  gtk_widget_set_valign(revealer_, GTK_ALIGN_END);
  gtk_widget_set_margin_bottom(revealer_, 16);
  label_ = gtk_label_new("");
  GtkWidget* frame = gtk_frame_new(nullptr);
  gtk_container_add(GTK_CONTAINER(frame), label_);
  gtk_container_add(GTK_CONTAINER(revealer_), frame);
#endif
}

GtkWidget* ToastView::widget() const {
  return revealer_;
}

void ToastView::Show(const std::string& message) {
#if KELPIE_LINUX_HAS_GTK
  if (label_ == nullptr) {
    return;
  }
  gtk_label_set_text(GTK_LABEL(label_), message.c_str());
  gtk_revealer_set_reveal_child(GTK_REVEALER(revealer_), TRUE);
  g_timeout_add(
      3000,
      +[](gpointer user_data) -> gboolean {
        gtk_revealer_set_reveal_child(GTK_REVEALER(user_data), FALSE);
        return G_SOURCE_REMOVE;
      },
      revealer_);
#endif
}

}  // namespace kelpie::linuxapp
