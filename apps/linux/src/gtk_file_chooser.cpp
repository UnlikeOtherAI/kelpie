#include "gtk_file_chooser.h"

#if KELPIE_LINUX_HAS_GTK
#include <utility>

namespace kelpie::linuxapp {
namespace {

void ApplyFileFilter(GtkFileChooser* chooser, const std::vector<std::string>& accept_types) {
  auto* filter = gtk_file_filter_new();
  gtk_file_filter_set_name(filter, "Accepted files");
  for (const auto& type : accept_types) {
    if (type.starts_with('.')) {
      const auto pattern = "*" + type;
      gtk_file_filter_add_pattern(filter, pattern.c_str());
    } else if (type.find('/') != std::string::npos) {
      gtk_file_filter_add_mime_type(filter, type.c_str());
    }
  }
  if (gtk_file_filter_get_needed(filter) != 0) {
    gtk_file_chooser_add_filter(chooser, filter);
  } else {
    g_object_ref_sink(filter);
    g_object_unref(filter);
  }
}

}  // namespace

void GtkFileChooserPanel::Open(const DesktopEngine::FileChooserRequest& request,
                               DesktopEngine::FileChooserCompletion complete) {
  if (dialog_ != nullptr) {
    complete({});
    return;
  }
  const auto action = request.directory ? GTK_FILE_CHOOSER_ACTION_SELECT_FOLDER
                                        : GTK_FILE_CHOOSER_ACTION_OPEN;
  dialog_ = gtk_file_chooser_native_new(request.title.empty() ? nullptr : request.title.c_str(),
                                        window_, action, nullptr, nullptr);
  auto* chooser = GTK_FILE_CHOOSER(dialog_);
  gtk_file_chooser_set_select_multiple(chooser, request.multiple);
  if (!request.directory && !request.accept_types.empty()) {
    ApplyFileFilter(chooser, request.accept_types);
  }

  complete_ = std::move(complete);
  auto* dialog = GTK_NATIVE_DIALOG(dialog_);
  gtk_native_dialog_set_modal(dialog, TRUE);
  g_signal_connect(dialog, "response", G_CALLBACK(+[](GtkNativeDialog*, int response, gpointer self) {
    static_cast<GtkFileChooserPanel*>(self)->Complete(response);
  }), this);
  gtk_native_dialog_show(dialog);
}

void GtkFileChooserPanel::Cancel() {
  if (dialog_ != nullptr) Complete(GTK_RESPONSE_CANCEL);
}

void GtkFileChooserPanel::Complete(int response) {
  auto* dialog = std::exchange(dialog_, nullptr);
  auto complete = std::exchange(complete_, {});
  std::vector<std::string> paths;
  if (response == GTK_RESPONSE_ACCEPT) {
    auto* files = gtk_file_chooser_get_filenames(GTK_FILE_CHOOSER(dialog));
    for (auto* file = files; file != nullptr; file = file->next) {
      paths.emplace_back(static_cast<const char*>(file->data));
    }
    g_slist_free_full(files, g_free);
  }
  g_signal_handlers_disconnect_by_data(dialog, this);
  gtk_native_dialog_destroy(GTK_NATIVE_DIALOG(dialog));
  g_object_unref(dialog);
  complete(std::move(paths));
}

}  // namespace kelpie::linuxapp
#endif
