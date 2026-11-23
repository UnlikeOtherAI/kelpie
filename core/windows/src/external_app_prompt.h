#pragma once

#include <windows.h>

#include <string>

namespace kelpie::windows {

// Confirms an app link (`slack:`, `mailto:`) with the person, then opens it
// with the app Windows registered for its scheme. Nothing is shown when no app
// handles the scheme or another prompt is already open.
void PromptToOpenExternalApp(HWND window, const std::string& requester, const std::string& url);

}  // namespace kelpie::windows
