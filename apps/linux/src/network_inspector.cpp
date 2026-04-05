#include "network_inspector.h"

#include "linux_app.h"

#if KELPIE_LINUX_HAS_GTK
#include <gtk/gtk.h>
#endif

namespace kelpie::linuxapp {
namespace {

#if KELPIE_LINUX_HAS_GTK
std::optional<std::string> FilterValue(GtkComboBoxText* combo) {
  const gchar* text = gtk_combo_box_text_get_active_text(combo);
  if (text == nullptr) {
    return std::nullopt;
  }
  const std::string value = text;
  g_free(const_cast<gchar*>(text));
  if (value == "All") {
    return std::nullopt;
  }
  if (value == "Browser") {
    return std::string("browser");
  }
  if (value == "JS") {
    return std::string("js");
  }
  return value;
}
#endif

}  // namespace

NetworkInspector::NetworkInspector(LinuxApp& app) : app_(app) {
#if KELPIE_LINUX_HAS_GTK
  root_ = gtk_box_new(GTK_ORIENTATION_VERTICAL, 8);
  gtk_widget_set_hexpand(root_, TRUE);
  gtk_widget_set_vexpand(root_, TRUE);
  GtkWidget* filters = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 6);
  gtk_box_pack_start(GTK_BOX(root_), filters, FALSE, FALSE, 0);

  method_filter_ = GTK_COMBO_BOX_TEXT(gtk_combo_box_text_new());
  type_filter_ = GTK_COMBO_BOX_TEXT(gtk_combo_box_text_new());
  source_filter_ = GTK_COMBO_BOX_TEXT(gtk_combo_box_text_new());

  for (const char* value : {"All", "GET", "POST", "PUT", "DELETE"}) {
    gtk_combo_box_text_append_text(method_filter_, value);
  }
  for (const char* value : {"All", "HTML", "JSON", "JS", "CSS", "Image", "Font", "XML", "Other"}) {
    gtk_combo_box_text_append_text(type_filter_, value);
  }
  for (const char* value : {"All", "Browser", "JS"}) {
    gtk_combo_box_text_append_text(source_filter_, value);
  }
  gtk_combo_box_set_active(GTK_COMBO_BOX(method_filter_), 0);
  gtk_combo_box_set_active(GTK_COMBO_BOX(type_filter_), 0);
  gtk_combo_box_set_active(GTK_COMBO_BOX(source_filter_), 0);

  gtk_box_pack_start(GTK_BOX(filters), GTK_WIDGET(method_filter_), FALSE, FALSE, 0);
  gtk_box_pack_start(GTK_BOX(filters), GTK_WIDGET(type_filter_), FALSE, FALSE, 0);
  gtk_box_pack_start(GTK_BOX(filters), GTK_WIDGET(source_filter_), FALSE, FALSE, 0);

  store_ = gtk_list_store_new(6, G_TYPE_STRING, G_TYPE_STRING, G_TYPE_INT, G_TYPE_STRING, G_TYPE_INT64,
                              G_TYPE_INT);
  GtkWidget* tree = gtk_tree_view_new_with_model(GTK_TREE_MODEL(store_));
  gtk_tree_view_insert_column_with_attributes(GTK_TREE_VIEW(tree), -1, "Method",
                                              gtk_cell_renderer_text_new(), "text", 0, nullptr);
  gtk_tree_view_insert_column_with_attributes(GTK_TREE_VIEW(tree), -1, "URL",
                                              gtk_cell_renderer_text_new(), "text", 1, nullptr);
  gtk_tree_view_insert_column_with_attributes(GTK_TREE_VIEW(tree), -1, "Status",
                                              gtk_cell_renderer_text_new(), "text", 2, nullptr);
  gtk_tree_view_insert_column_with_attributes(GTK_TREE_VIEW(tree), -1, "Type",
                                              gtk_cell_renderer_text_new(), "text", 3, nullptr);
  gtk_tree_view_insert_column_with_attributes(GTK_TREE_VIEW(tree), -1, "Size",
                                              gtk_cell_renderer_text_new(), "text", 4, nullptr);
  gtk_tree_view_insert_column_with_attributes(GTK_TREE_VIEW(tree), -1, "Time",
                                              gtk_cell_renderer_text_new(), "text", 5, nullptr);

  GtkWidget* scroll = gtk_scrolled_window_new(nullptr, nullptr);
  gtk_widget_set_hexpand(scroll, TRUE);
  gtk_widget_set_vexpand(scroll, TRUE);
  gtk_scrolled_window_set_policy(GTK_SCROLLED_WINDOW(scroll), GTK_POLICY_AUTOMATIC, GTK_POLICY_AUTOMATIC);
  gtk_container_add(GTK_CONTAINER(scroll), tree);
  gtk_box_pack_start(GTK_BOX(root_), scroll, TRUE, TRUE, 0);

  auto refresh_cb = +[](GtkComboBox*, gpointer user_data) {
    static_cast<NetworkInspector*>(user_data)->Refresh();
  };
  g_signal_connect(method_filter_, "changed", G_CALLBACK(refresh_cb), this);
  g_signal_connect(type_filter_, "changed", G_CALLBACK(refresh_cb), this);
  g_signal_connect(source_filter_, "changed", G_CALLBACK(refresh_cb), this);
#endif
}

GtkWidget* NetworkInspector::widget() const {
  return root_;
}

void NetworkInspector::Refresh() {
#if KELPIE_LINUX_HAS_GTK
  if (store_ == nullptr) {
    return;
  }
  gtk_list_store_clear(store_);
  const auto entries = app_.NetworkEntries(FilterValue(method_filter_), FilterValue(type_filter_),
                                           FilterValue(source_filter_))["entries"];
  for (const auto& entry : entries) {
    GtkTreeIter iter;
    gtk_list_store_append(store_, &iter);
    std::string url = entry.value("url", "");
    if (url.size() > 80) {
      url = url.substr(0, 77) + "...";
    }
    gtk_list_store_set(store_,
                       &iter,
                       0,
                       entry.value("method", "").c_str(),
                       1,
                       url.c_str(),
                       2,
                       entry.value("status", 0),
                       3,
                       entry.value("type", "").c_str(),
                       4,
                       static_cast<gint64>(entry.value("size", 0)),
                       5,
                       entry["timing"].value("total", 0),
                       -1);
  }
#endif
}

}  // namespace kelpie::linuxapp
