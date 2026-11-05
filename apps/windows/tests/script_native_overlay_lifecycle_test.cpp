#include "script_native_overlay.h"
#include <cassert>
#include <stdexcept>

int main() {
  const HINSTANCE instance=GetModuleHandleW(nullptr);
  HWND owner=CreateWindowExW(0,L"STATIC",L"",WS_OVERLAPPED,0,0,100,100,
                             nullptr,nullptr,instance,nullptr);
  assert(owner);
  HWND viewport=CreateWindowExW(0,L"STATIC",L"",WS_CHILD,0,0,80,80,
                                owner,nullptr,instance,nullptr);
  assert(viewport);
  {
    kelpie::windows::ScriptNativeOverlay overlay(viewport,owner,{});
    // The first presentation must not read a JSON object member from null.
    overlay.Show({{"playing",false},{"_presentationRevision",std::uint64_t{1}}},{},{});
    assert(!overlay.RetireIfRevision(0));
    overlay.Show({{"playing",false},{"_presentationRevision",std::uint64_t{2}}},{},{});
    assert(!overlay.RetireIfRevision(1));
    assert(overlay.RetireIfRevision(2));
  }
  DestroyWindow(viewport);
  DestroyWindow(owner);
}