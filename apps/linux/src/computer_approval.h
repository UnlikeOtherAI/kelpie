#pragma once
#include "kelpie/peer_approval.h"
#if KELPIE_LINUX_HAS_GTK
#include <gtk/gtk.h>
#else
typedef struct _GtkWindow GtkWindow;
typedef struct _GtkWidget GtkWidget;
#endif

namespace kelpie::linuxapp {
class ComputerApprovalView {
 public:
  ComputerApprovalView(PeerApprovalQueue& approvals, GtkWindow* parent);
  ~ComputerApprovalView();
  void Poll();
 private:
  PeerApprovalQueue& approvals_;
  GtkWindow* parent_;
  GtkWidget* dialog_ = nullptr;
  std::string request_id_;
};
}
