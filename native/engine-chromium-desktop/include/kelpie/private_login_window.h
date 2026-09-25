#pragma once
#include <functional>
#include <string>

namespace kelpie {
// UI-thread only. This hosted login surface is never registered as an engine
// tab, so browser automation, history and session persistence cannot reach it.
bool OpenPrivateLoginWindow(const std::string& url, std::function<void()> cancelled);
// Returns true after all private browser/window references have been released.
bool ClosePrivateLoginWindow();
}
