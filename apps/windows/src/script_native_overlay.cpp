#include "script_native_overlay.h"
#include "script_frame_compositor.h"
#include <algorithm>
#include <vector>
#include <cstring>
#include <stdexcept>
#include <utility>

namespace kelpie::windows {
namespace {
UINT ExactWindowDpi(HWND window) {
  // The target supports Windows 7; resolve the per-window API exactly as the
  // shell metrics do, but fail closed here when a physical DPI is unavailable.
  using GetDpiForWindowFn=UINT(WINAPI*)(HWND);
  static const auto getDpi=reinterpret_cast<GetDpiForWindowFn>(
      GetProcAddress(GetModuleHandleW(L"user32.dll"),"GetDpiForWindow"));
  return window && getDpi ? getDpi(window) : 0;
}
LRESULT CALLBACK CanvasProc(HWND hwnd,UINT message,WPARAM wparam,LPARAM lparam) {
  if (message==WM_NCHITTEST) return HTTRANSPARENT;
  if (message==WM_MOUSEACTIVATE) return MA_NOACTIVATE;
  return DefWindowProcW(hwnd,message,wparam,lparam);
}
void RegisterOverlayClasses() {
  static const bool registered = [] {
    WNDCLASSW canvas{}; canvas.lpfnWndProc=CanvasProc; canvas.hInstance=GetModuleHandleW(nullptr);
    canvas.lpszClassName=L"KelpieScriptPresentation"; RegisterClassW(&canvas);
    return true;
  }();
  (void)registered;
}
}
ScriptNativeOverlay::ScriptNativeOverlay(HWND viewport,HWND owner,DocumentGuard guard)
    : viewport_(viewport),owner_(owner),guard_(std::move(guard)) {
  RegisterOverlayClasses();
  const auto instance=GetModuleHandleW(nullptr);
  canvas_=CreateWindowExW(WS_EX_LAYERED|WS_EX_TRANSPARENT|WS_EX_TOOLWINDOW|WS_EX_NOACTIVATE,
      L"KelpieScriptPresentation",L"",WS_POPUP,0,0,1,1,owner_,nullptr,instance,nullptr);
  WNDCLASSW controls{}; controls.lpfnWndProc=StopProc; controls.hInstance=instance;
  controls.lpszClassName=L"KelpieScriptStop"; controls.hbrBackground=GetSysColorBrush(COLOR_BTNFACE); RegisterClassW(&controls);
  stop_window_=CreateWindowExW(WS_EX_TOOLWINDOW|WS_EX_NOACTIVATE,L"KelpieScriptStop",L"Stop script",
      WS_POPUP,0,0,88,32,owner_,nullptr,instance,this);
  button_=CreateWindowExW(0,L"BUTTON",L"Stop script",WS_CHILD|WS_VISIBLE|BS_PUSHBUTTON,
      0,0,88,32,stop_window_,reinterpret_cast<HMENU>(1),instance,nullptr);
  if(!canvas_ || !stop_window_ || !button_) {
    if(canvas_) DestroyWindow(canvas_); if(stop_window_) DestroyWindow(stop_window_);
    throw std::runtime_error("CAPTURE_NATIVE_PRESENTATION_FAILED");
  }
  SendMessageW(button_,WM_SETFONT,reinterpret_cast<WPARAM>(GetStockObject(DEFAULT_GUI_FONT)),TRUE);
}
ScriptNativeOverlay::~ScriptNativeOverlay() {
  stop_={}; if(stop_window_) KillTimer(stop_window_,1);
  if (canvas_) DestroyWindow(canvas_);
  if (stop_window_) DestroyWindow(stop_window_);
}
LRESULT CALLBACK ScriptNativeOverlay::StopProc(HWND hwnd,UINT message,WPARAM wparam,LPARAM lparam) {
  auto* self=reinterpret_cast<ScriptNativeOverlay*>(GetWindowLongPtrW(hwnd,GWLP_USERDATA));
  if (message==WM_NCCREATE) {
    self=static_cast<ScriptNativeOverlay*>(reinterpret_cast<CREATESTRUCTW*>(lparam)->lpCreateParams);
    SetWindowLongPtrW(hwnd,GWLP_USERDATA,reinterpret_cast<LONG_PTR>(self));
  }
  if(message==WM_TIMER && self) {
    const auto revision=self->shown_.value("_presentationRevision",std::uint64_t{});
    try {
      auto shown=self->shown_;
      if(!shown.value("playing",false) && !shown.value("detachedMarker",false)) return 0;
      shown["elapsedMs"]=shown.value("elapsedMs",0.0)+GetTickCount64()-self->shown_at_;
      self->Show(shown,self->stop_,self->valid_);
    } catch(...) {
      const auto stop=self->stop_;
      const bool retired=self->RetireIfRevision(revision);
      try { if(retired && stop) stop(); } catch(...) {}
    }
    return 0;
  }
  if (message==WM_COMMAND && LOWORD(wparam)==1 && HIWORD(wparam)==BN_CLICKED && self && self->stop_) { self->stop_(); return 0; }
  if (message==WM_MOUSEACTIVATE) return MA_NOACTIVATE;
  return DefWindowProcW(hwnd,message,wparam,lparam);
}
bool ScriptNativeOverlay::RetireIfRevision(std::uint64_t revision) {
  if(shown_.value("_presentationRevision",std::uint64_t{})!=revision) return false;
  RetireDetached(); return true;
}
void ScriptNativeOverlay::RetireDetached() {
  liveGeometry_.Lose();
  shown_={{"playing",false}}; stop_={}; valid_={}; detachedAnchored_=false;
  KillTimer(stop_window_,1);
  if(canvas_) ShowWindow(canvas_,SW_HIDE);
  if(stop_window_) ShowWindow(stop_window_,SW_HIDE);
}
void ScriptNativeOverlay::Show(const nlohmann::json& presentation,std::function<void()> stop,std::function<bool()> valid) {
  const bool detached=presentation.value("detachedMarker",false);
  const auto previousRevision=shown_.value("_presentationRevision",std::uint64_t{});
  const auto revision=presentation.value("_presentationRevision",std::uint64_t{});
  stop_=detached ? std::function<void()>{} : std::move(stop);
  valid_=detached ? std::move(valid) : std::function<bool()>{};
  shown_=presentation; shown_at_=GetTickCount64();
  const bool playing=presentation.value("playing",false);
  if(!detached) {
    detachedAnchored_=false;
    if(playing && !presentation.contains("marker")) liveGeometry_.Lose();
  }
  if(detached) {
    const auto validity=valid_;const auto documentGuard=guard_;
    const bool allowed=AuthorizeDetachedMarker(presentation,validity,documentGuard);
    // A reentrant newer presentation owns the canvas; never retire it.
    if(shown_.value("_presentationRevision",std::uint64_t{})!=revision) return;
    if(!allowed) { RetireDetached(); return; }
  }
  const HWND foreground=GetForegroundWindow();
  const bool foregroundOk=foreground==owner_ || (!detached && foreground==stop_window_);
  if ((!playing && !detached) || !IsWindowVisible(owner_) || !IsWindowVisible(viewport_) ||
      IsIconic(owner_) || !IsWindowEnabled(owner_) || !foregroundOk) {
    if(detached) { RetireDetached(); return; }
    liveGeometry_.Lose();
    if (playing) SetTimer(stop_window_,1,33,nullptr); else KillTimer(stop_window_,1);
    if (canvas_) ShowWindow(canvas_,SW_HIDE);
    if (stop_window_) ShowWindow(stop_window_,SW_HIDE);
    return;
  }
  RECT rect{}; POINT origin{};
  if(!GetClientRect(viewport_,&rect) || !ClientToScreen(viewport_,&origin)) {
    if(detached) RetireDetached(); else liveGeometry_.Lose();
    return;
  }
  const int width=rect.right-rect.left,height=rect.bottom-rect.top;
  if (width<=0 || height<=0 || static_cast<std::uint64_t>(width)*height>8388608) {
    if(detached) RetireDetached(); else liveGeometry_.Lose();
    return;
  }
  if(detached || (playing && presentation.contains("marker"))) {
    DetachedMarkerAnchor current;
    try {
      DWORD ownerPid=0,viewportPid=0;
      GetWindowThreadProcessId(owner_,&ownerPid);GetWindowThreadProcessId(viewport_,&viewportPid);
      if(ownerPid!=GetCurrentProcessId() || viewportPid!=GetCurrentProcessId() ||
         GetAncestor(viewport_,GA_ROOT)!=owner_) {
        if(detached) RetireDetached(); else liveGeometry_.Lose();
        return;
      }
      current={origin.x,origin.y,width,height,ExactWindowDpi(viewport_),revision,
        presentation.at("runId").get<std::string>(),presentation.at("tabId").get<std::string>(),
        presentation.at("documentVersion").get<std::string>(),presentation.at("generation").get<std::uint64_t>(),
        presentation.at("marker").at("actionIndex").get<int>()};
    } catch(...) {
      if(detached) RetireDetached(); else liveGeometry_.Lose();
      return;
    }
    if(!detached) {
      liveGeometry_.Observe(current);
    } else {
    if(!liveGeometry_.Allows(current)) { RetireDetached(); return; }
    if(detachedAnchored_ && previousRevision==revision && !SameDetachedMarkerAnchor(anchor_,current)) {
      RetireDetached(); return;
    }
    anchor_=std::move(current);detachedAnchored_=true;
    ShowWindow(stop_window_,SW_HIDE);
    }
  }
  if(!detached) {
    SetWindowPos(stop_window_,HWND_TOP,origin.x+std::max(0,width-96),origin.y+8,88,32,
      SWP_NOACTIVATE|SWP_SHOWWINDOW|SWP_NOZORDER|SWP_NOOWNERZORDER);
  }
  if(!SetTimer(stop_window_,1,33,nullptr) && detached) { RetireDetached(); return; }
  if(!presentation.contains("marker") && !presentation.contains("pointer") && !presentation.contains("commentary")) {
    ShowWindow(canvas_,SW_HIDE); return;
  }
  ScriptMediaFrame frame; frame.width=width; frame.height=height; frame.stride=width*4;
  frame.bgra.resize(static_cast<std::size_t>(frame.stride)*height,0);
  DrawScriptOverlay(frame,presentation);
  BITMAPINFO info{}; info.bmiHeader.biSize=sizeof(BITMAPINFOHEADER); info.bmiHeader.biWidth=width;
  info.bmiHeader.biHeight=-height; info.bmiHeader.biPlanes=1; info.bmiHeader.biBitCount=32; info.bmiHeader.biCompression=BI_RGB;
  HDC screen=GetDC(nullptr), memory=CreateCompatibleDC(screen); void* bits=nullptr;
  HBITMAP bitmap=screen && memory ? CreateDIBSection(screen,&info,DIB_RGB_COLORS,&bits,nullptr,0) : nullptr;
  if(detached && (!screen || !memory || !bitmap || !bits)) {
    if(bitmap) DeleteObject(bitmap);
    if(memory) DeleteDC(memory);
    if(screen) ReleaseDC(nullptr,screen);
    throw std::runtime_error("CAPTURE_NATIVE_PRESENTATION_FAILED");
  }
  if (bitmap && bits) {
    std::memcpy(bits,frame.bgra.data(),frame.bgra.size());
    HGDIOBJ previous=SelectObject(memory,bitmap);
    if(detached && (!previous || previous==HGDI_ERROR)) {
      DeleteObject(bitmap); DeleteDC(memory); ReleaseDC(nullptr,screen);
      throw std::runtime_error("CAPTURE_NATIVE_PRESENTATION_FAILED");
    }
    SIZE size{width,height}; POINT source{}; BLENDFUNCTION blend{AC_SRC_OVER,0,255,AC_SRC_ALPHA};
    const bool updated=UpdateLayeredWindow(canvas_,screen,&origin,&size,memory,&source,0,&blend,ULW_ALPHA)!=FALSE;
    if(!updated) {
      SelectObject(memory,previous); DeleteObject(bitmap); DeleteDC(memory); ReleaseDC(nullptr,screen);
      throw std::runtime_error("CAPTURE_NATIVE_PRESENTATION_FAILED");
    }
    SelectObject(memory,previous);
    const bool positioned=SetWindowPos(canvas_,HWND_TOP,origin.x,origin.y,width,height,
      SWP_NOACTIVATE|SWP_SHOWWINDOW|SWP_NOZORDER|SWP_NOOWNERZORDER)!=FALSE;
    if(detached && !positioned) {
      DeleteObject(bitmap); DeleteDC(memory); ReleaseDC(nullptr,screen);
      throw std::runtime_error("CAPTURE_NATIVE_PRESENTATION_FAILED");
    }
    // Keep only the small native Stop control interactive above presentation.
    if(!detached) SetWindowPos(stop_window_,HWND_TOP,0,0,0,0,SWP_NOMOVE|SWP_NOSIZE|SWP_NOACTIVATE|SWP_NOZORDER|SWP_NOOWNERZORDER);
  }
  if (bitmap) DeleteObject(bitmap);
  DeleteDC(memory); ReleaseDC(nullptr,screen);
}
}
