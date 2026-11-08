#pragma once

// The complete native browser UI, tabs and runtime. Link Kelpie::Browser.
#include "windows_app.h"
#include "kelpie/bootstrap.h"

namespace kelpie::windows {
using BrowserSession = WindowsApp;
using BrowserConfiguration = AppConfig;
}
