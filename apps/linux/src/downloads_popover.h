#pragma once

#if KELPIE_LINUX_HAS_GTK
#include <gtk/gtk.h>
#include "kelpie/download_history.h"

namespace kelpie::linuxapp {
void AttachDownloadsPopover(GtkWidget* button, DownloadHistory& history);
}
#endif
