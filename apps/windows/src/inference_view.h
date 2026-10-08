#pragma once
#include <windows.h>
#include "inference_service.h"
namespace kelpie::windows {
void ShowInferenceSettings(HINSTANCE instance, HWND owner, InferenceService& service);
}
