#include "downloads_popover.h"

#if KELPIE_LINUX_HAS_GTK
#include <limits>

namespace kelpie::linuxapp {
namespace {
struct Popup {
  DownloadHistory& history;
  GtkWidget* rows;
  GtkWidget* clear;
  uint64_t revision = std::numeric_limits<uint64_t>::max();
  guint timer = 0;
};

void Reveal(GtkButton* button, gpointer) {
  auto* path = static_cast<const char*>(g_object_get_data(G_OBJECT(button), "path"));
  auto* file = g_file_new_for_path(path);
  auto* uri = g_file_get_uri(file);
  auto* parent = g_file_get_parent(file);
  auto* folder = g_file_get_uri(parent);
  const char* selection[] = {uri, nullptr};
  auto* bus = g_bus_get_sync(G_BUS_TYPE_SESSION, nullptr, nullptr);
  if (bus) {
    g_dbus_connection_call(bus, "org.freedesktop.FileManager1", "/org/freedesktop/FileManager1",
                           "org.freedesktop.FileManager1", "ShowItems", g_variant_new("(^ass)", selection, ""),
                           nullptr, G_DBUS_CALL_FLAGS_NONE, 5000, nullptr,
                           +[](GObject* source, GAsyncResult* result, gpointer raw) {
      auto* reply = g_dbus_connection_call_finish(G_DBUS_CONNECTION(source), result, nullptr);
      if (reply) g_variant_unref(reply);
      else gtk_show_uri_on_window(nullptr, static_cast<char*>(raw), GDK_CURRENT_TIME, nullptr);
      g_free(raw);
    }, folder);
    g_object_unref(bus);
  } else {
    gtk_show_uri_on_window(nullptr, folder, GDK_CURRENT_TIME, nullptr);
    g_free(folder);
  }
  g_free(uri);
  g_object_unref(parent);
  g_object_unref(file);
}

gboolean Refresh(gpointer data) {
  auto& popup = *static_cast<Popup*>(data);
  if (popup.revision == popup.history.revision()) return G_SOURCE_CONTINUE;
  popup.revision = popup.history.revision();
  gtk_container_foreach(GTK_CONTAINER(popup.rows), +[](GtkWidget* child, gpointer) { gtk_widget_destroy(child); }, nullptr);
  bool can_clear = false;
  for (const auto& item : popup.history.items()) {
    auto* row = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 4);
    auto* label = gtk_label_new((item.name + "  —  " + DownloadHistory::Label(item.state)).c_str());
    gtk_label_set_xalign(GTK_LABEL(label), 0);
    gtk_label_set_ellipsize(GTK_LABEL(label), PANGO_ELLIPSIZE_MIDDLE);
    if (item.state == DownloadHistory::State::complete) {
      auto* open = gtk_button_new();
      gtk_container_add(GTK_CONTAINER(open), label);
      gtk_button_set_relief(GTK_BUTTON(open), GTK_RELIEF_NONE);
      gtk_box_pack_start(GTK_BOX(row), open, TRUE, TRUE, 0);
      auto* reveal = gtk_button_new_from_icon_name("system-search-symbolic", GTK_ICON_SIZE_MENU);
      gtk_button_set_relief(GTK_BUTTON(reveal), GTK_RELIEF_NONE);
      gtk_widget_set_tooltip_text(reveal, "Show in file manager");
      gtk_box_pack_end(GTK_BOX(row), reveal, FALSE, FALSE, 0);
      for (auto* control : {open, reveal}) {
        g_object_set_data_full(G_OBJECT(control), "path", g_strdup(item.path.c_str()), g_free);
      }
      g_signal_connect(open, "clicked", G_CALLBACK(+[](GtkButton* b, gpointer) {
        auto* uri = g_filename_to_uri(static_cast<const char*>(g_object_get_data(G_OBJECT(b), "path")), nullptr, nullptr);
        if (uri) gtk_show_uri_on_window(nullptr, uri, GDK_CURRENT_TIME, nullptr);
        g_free(uri);
      }), nullptr);
      g_signal_connect(reveal, "clicked", G_CALLBACK(Reveal), nullptr);
    } else {
      gtk_box_pack_start(GTK_BOX(row), label, TRUE, TRUE, 0);
    }
    gtk_box_pack_start(GTK_BOX(popup.rows), row, FALSE, FALSE, 0);
    can_clear |= item.state != DownloadHistory::State::downloading;
  }
  if (popup.history.items().empty()) {
    gtk_box_pack_start(GTK_BOX(popup.rows), gtk_label_new("No downloads"), FALSE, FALSE, 2);
  }
  gtk_widget_set_sensitive(popup.clear, can_clear);
  gtk_widget_show_all(popup.rows);
  return G_SOURCE_CONTINUE;
}
}  // namespace

void AttachDownloadsPopover(GtkWidget* button, DownloadHistory& history) {
  gtk_widget_show_all(gtk_bin_get_child(GTK_BIN(button)));
  gtk_widget_set_no_show_all(button, TRUE);
  history.visibility_changed = [button](bool visible) { gtk_widget_set_visible(button, visible); };
  gtk_widget_set_visible(button, !history.items().empty());
  g_signal_connect(button, "destroy", G_CALLBACK(+[](GtkWidget*, gpointer data) {
    static_cast<DownloadHistory*>(data)->visibility_changed = {};
  }), &history);
  auto popover = gtk_popover_new(button);
  auto box = gtk_box_new(GTK_ORIENTATION_VERTICAL, 8);
  gtk_container_set_border_width(GTK_CONTAINER(box), 10);
  auto header = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 8);
  gtk_box_pack_start(GTK_BOX(header), gtk_label_new("Downloads"), FALSE, FALSE, 0);
  auto clear = gtk_button_new_with_label("Clear");
  gtk_box_pack_end(GTK_BOX(header), clear, FALSE, FALSE, 0);
  gtk_box_pack_start(GTK_BOX(box), header, FALSE, FALSE, 0);
  auto scroll = gtk_scrolled_window_new(nullptr, nullptr);
  gtk_scrolled_window_set_policy(GTK_SCROLLED_WINDOW(scroll), GTK_POLICY_NEVER, GTK_POLICY_AUTOMATIC);
  gtk_widget_set_size_request(scroll, 300, 140);
  auto rows = gtk_box_new(GTK_ORIENTATION_VERTICAL, 4);
  gtk_container_add(GTK_CONTAINER(scroll), rows);
  gtk_box_pack_start(GTK_BOX(box), scroll, TRUE, TRUE, 0);
  gtk_container_add(GTK_CONTAINER(popover), box);
  auto* popup = new Popup{history, rows, clear};
  g_signal_connect(clear, "clicked", G_CALLBACK(+[](GtkButton*, gpointer raw) {
    static_cast<Popup*>(raw)->history.ClearFinished();
    Refresh(raw);
  }), popup);
  g_signal_connect(popover, "show", G_CALLBACK(+[](GtkWidget*, gpointer raw) {
    auto* state = static_cast<Popup*>(raw);
    Refresh(raw);
    state->timer = g_timeout_add(250, Refresh, raw);
  }), popup);
  g_signal_connect(popover, "hide", G_CALLBACK(+[](GtkWidget*, gpointer raw) {
    auto* state = static_cast<Popup*>(raw);
    if (state->timer) { g_source_remove(state->timer); state->timer = 0; }
  }), popup);
  g_object_set_data_full(G_OBJECT(popover), "download-state", popup, +[](gpointer raw) {
    auto* state = static_cast<Popup*>(raw);
    if (state->timer) g_source_remove(state->timer);
    delete state;
  });
  g_signal_connect_object(button, "clicked", G_CALLBACK(gtk_widget_show_all), popover, G_CONNECT_SWAPPED);
  g_signal_connect_object(button, "destroy", G_CALLBACK(gtk_widget_destroy), popover, G_CONNECT_SWAPPED);
}
}  // namespace kelpie::linuxapp
#endif
