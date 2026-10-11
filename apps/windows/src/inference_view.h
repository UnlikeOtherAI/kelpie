#pragma once
#include <windows.h>
#include "inference_service.h"
#include "kelpie/desktop_engine.h"
namespace kelpie::windows {
void ShowInferenceSettings(HINSTANCE instance, HWND owner, InferenceService& service, DesktopEngine& engine);
}
