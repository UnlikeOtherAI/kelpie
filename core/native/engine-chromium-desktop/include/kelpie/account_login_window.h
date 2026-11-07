#pragma once
#include <functional>
#include <string>

namespace kelpie {
// UI-thread only. The account login window is a hosted Kelpie surface for the
// UOA login/register flow. It is never registered as an engine tab, so browser
// automation, history and session persistence cannot reach it. By design it
// uses the same request context as unpartitioned tabs (the default profile),
// so a Google or UOA sign-in completed here is shared with every ordinary tab:
// cookies, storage and everything else in that profile.
// Returns false when no window could be opened (including builds without CEF).
bool OpenAccountLoginWindow(const std::string& url, std::function<void()> cancelled);
// Returns true after all login browser/window references have been released.
bool CloseAccountLoginWindow();
}
