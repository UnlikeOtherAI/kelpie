#include "script_capture_service.h"
#include "script_native_overlay.h"

namespace kelpie::windows {
WindowsScriptService::WindowsScriptService(HWND viewport,HWND owner,Marshal marshal,DocumentGuard guard)
    :viewport_(viewport),owner_(owner),marshal_(std::move(marshal)),guard_(std::move(guard)) {}
WindowsScriptService::~WindowsScriptService() {
  overlay_.reset();
  for(const auto& [id,entry]:entries_) {
    RemoveCaptureFile(entry.path,entry.identity);
    std::error_code ignored; std::filesystem::remove(entry.path.parent_path(),ignored);
  }
}
}
