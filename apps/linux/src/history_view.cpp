#include "history_view.h"

#include "linux_app.h"

#if MOLLOTOV_LINUX_HAS_GTK
#include <gtk/gtk.h>
#endif

namespace mollotov::linuxapp {

HistoryView::HistoryView(LinuxApp& app) : app_(app) {
#if MOLLOTOV_LINUX_HAS_GTK
  root_ = gtk_scrolled_window_new(nullptr, nullptr);
  list_ = gtk_list_box_new();
  gtk_widget_set_hexpand(root_, TRUE);
  gtk_widget_set_vexpand(root_, TRUE);
  gtk_scrolled_window_set_policy(GTK_SCROLLED_WINDOW(root_), GTK_POLICY_AUTOMATIC, GTK_POLICY_AUTOMATIC);
  gtk_container_add(GTK_CONTAINER(root_), list_);
#endif
}

GtkWidget* HistoryView::widget() const {
  return root_;
}

void HistoryView::Refresh() {
#if MOLLOTOV_LINUX_HAS_GTK
  if (list_ == nullptr) {
    return;
  }
  GList* children = gtk_container_get_children(GTK_CONTAINER(list_));
  for (GList* item = children; item != nullptr; item = item->next) {
    gtk_widget_destroy(GTK_WIDGET(item->data));
  }
  g_list_free(children);

  const auto entries = nlohmann::json::parse(app_.HistoryJson());
  for (const auto& entry : entries) {
    GtkWidget* row = gtk_list_box_row_new();
    const std::string text = entry.value("title", "") + "\n" + entry.value("url", "");
    GtkWidget* label = gtk_label_new(text.c_str());
    gtk_label_set_xalign(GTK_LABEL(label), 0.0);
    gtk_container_add(GTK_CONTAINER(row), label);
    g_object_set_data_full(G_OBJECT(row),
                           "mollotov-url",
                           g_strdup(entry.value("url", "").c_str()),
                           g_free);
    gtk_container_add(GTK_CONTAINER(list_), row);
  }
  g_signal_handlers_disconnect_by_data(list_, &app_);
  g_signal_connect(list_, "row-activated", G_CALLBACK(+[](GtkListBox*, GtkListBoxRow* row, gpointer user_data) {
                     auto* app_ptr = static_cast<LinuxApp*>(user_data);
                     const char* url = static_cast<const char*>(g_object_get_data(G_OBJECT(row), "mollotov-url"));
                     if (url != nullptr) {
                       app_ptr->Navigate(url);
                     }
                   }),
                   &app_);
  gtk_widget_show_all(list_);
#endif
}

}  // namespace mollotov::linuxapp
