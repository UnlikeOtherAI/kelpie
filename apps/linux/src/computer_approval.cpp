#include "computer_approval.h"

namespace kelpie::linuxapp {
ComputerApprovalView::ComputerApprovalView(PeerApprovalQueue& approvals, GtkWindow* parent)
    : approvals_(approvals), parent_(parent) { approvals_.SetAvailable(true); }
ComputerApprovalView::~ComputerApprovalView() {
  approvals_.SetAvailable(false);
#if KELPIE_LINUX_HAS_GTK
  if (dialog_) gtk_widget_destroy(dialog_);
#endif
}

void ComputerApprovalView::Poll() {
#if KELPIE_LINUX_HAS_GTK
  const auto request = approvals_.Pending();
  if (dialog_) {
    if (request.is_null() || request.at("requestId") != request_id_) {
      gtk_widget_destroy(dialog_); dialog_ = nullptr;
    }
    return;
  }
  if (request.is_null()) return;
  request_id_ = request.at("requestId");
  dialog_ = gtk_message_dialog_new(parent_, GTK_DIALOG_DESTROY_WITH_PARENT, GTK_MESSAGE_QUESTION,
      GTK_BUTTONS_NONE, "Allow %s to control Kelpie?", request.at("sourceAddress").get<std::string>().c_str());
  gtk_window_set_title(GTK_WINDOW(dialog_), "Allow this computer?");
  gtk_window_set_modal(GTK_WINDOW(dialog_), TRUE);
  gtk_message_dialog_format_secondary_text(GTK_MESSAGE_DIALOG(dialog_),
      "Name (self-reported): %s\n\nAllow all clients at this IP to control Kelpie. This stays allowed until you revoke it in Settings.",
      request.at("clientName").get<std::string>().c_str());
  gtk_dialog_add_buttons(GTK_DIALOG(dialog_), "Deny", GTK_RESPONSE_REJECT, "Allow computer", GTK_RESPONSE_ACCEPT, nullptr);
  gtk_dialog_set_default_response(GTK_DIALOG(dialog_), GTK_RESPONSE_REJECT);
  g_signal_connect(dialog_, "response", G_CALLBACK(+[](GtkDialog*, gint response, gpointer raw) {
    auto& self = *static_cast<ComputerApprovalView*>(raw);
    if (response == GTK_RESPONSE_ACCEPT) {
      if (!self.approvals_.Approve(self.request_id_)) {
        gtk_message_dialog_format_secondary_text(GTK_MESSAGE_DIALOG(self.dialog_), "Could not save approval, or the request expired. Try again.");
        return;
      }
    } else self.approvals_.Deny(self.request_id_);
    gtk_widget_destroy(self.dialog_); self.dialog_ = nullptr;
  }), this);
  gtk_widget_show_all(dialog_);
#endif
}
}  // namespace kelpie::linuxapp
