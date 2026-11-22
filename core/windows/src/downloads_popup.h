#pragma once

#include <windows.h>
#include "../../native/engine-chromium-desktop/include/kelpie/download_history.h"

namespace kelpie::windows {
void ShowDownloadsPopup(HWND parent, HWND anchor, DownloadHistory& history);
}
