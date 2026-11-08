#pragma once

#include <cstdint>
#include <functional>

#include "include/cef_app.h"

namespace kelpie {

CefRefPtr<CefApp> CreateDesktopCefApp();
void SetDesktopCefMessagePumpScheduler(std::function<void(std::int64_t)> scheduler);

}  // namespace kelpie
