#include "script_native_overlay.h"
#include "script_frame_compositor.h"
#include <algorithm>
#include <vector>
#include <cstring>
#include <stdexcept>

namespace kelpie::windows {
namespace {
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
ScriptNativeOverlay::ScriptNativeOverlay(HWND viewport,HWND owner) : viewport_(viewport),owner_(owner) {
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
  if(message==WM_TIMER && self && self->shown_.value("playing",false)) {
    auto shown=self->shown_;
    if(!shown.value("captureLatched",false))
      shown["elapsedMs"]=shown.value("elapsedMs",0.0)+GetTickCount64()-self->shown_at_;
    try { self->Show(shown,self->stop_); } catch(...) { KillTimer(hwnd,1); if(self->canvas_) ShowWindow(self->canvas_,SW_HIDE); if(self->stop_) self->stop_(); } return 0;
  }
  if (message==WM_COMMAND && LOWORD(wparam)==1 && HIWORD(wparam)==BN_CLICKED && self && self->stop_) { self->stop_(); return 0; }
  if (message==WM_MOUSEACTIVATE) return MA_NOACTIVATE;
  return DefWindowProcW(hwnd,message,wparam,lparam);
}
void ScriptNativeOverlay::Show(const nlohmann::json& presentation,std::function<void()> stop) {
  stop_=std::move(stop);
  shown_=presentation; shown_at_=GetTickCount64();
  const bool playing=presentation.value("playing",false);
  // Keep a policy timer during a capture latch: foreground changes must hide
  // popups even while the sampled presentation timeline remains frozen.
  if(playing) SetTimer(stop_window_,1,33,nullptr);
  else KillTimer(stop_window_,1);
  const HWND foreground=GetForegroundWindow();
  if (!playing || !IsWindowVisible(owner_) || !IsWindowVisible(viewport_) ||
      IsIconic(owner_) || !IsWindowEnabled(owner_) ||
      (foreground!=owner_ && foreground!=stop_window_)) {
    if (canvas_) ShowWindow(canvas_,SW_HIDE);
    if (stop_window_) ShowWindow(stop_window_,SW_HIDE);
    return;
  }
  RECT rect{}; GetClientRect(viewport_,&rect);
  const int width=rect.right-rect.left,height=rect.bottom-rect.top;
  if (width<=0 || height<=0 || static_cast<std::uint64_t>(width)*height>8388608) return;
  POINT origin{}; ClientToScreen(viewport_,&origin);
  SetWindowPos(stop_window_,HWND_TOP,origin.x+std::max(0,width-96),origin.y+8,88,32,SWP_NOACTIVATE|SWP_SHOWWINDOW|SWP_NOZORDER|SWP_NOOWNERZORDER);
  if(!presentation.contains("marker") && !presentation.contains("pointer") && !presentation.contains("commentary")) {
    ShowWindow(canvas_,SW_HIDE); return;
  }
  ScriptMediaFrame frame; frame.width=width; frame.height=height; frame.stride=width*4;
  frame.bgra.resize(static_cast<std::size_t>(frame.stride)*height,0);
  DrawScriptOverlay(frame,presentation);
  BITMAPINFO info{}; info.bmiHeader.biSize=sizeof(BITMAPINFOHEADER); info.bmiHeader.biWidth=width;
  info.bmiHeader.biHeight=-height; info.bmiHeader.biPlanes=1; info.bmiHeader.biBitCount=32; info.bmiHeader.biCompression=BI_RGB;
  HDC screen=GetDC(nullptr), memory=CreateCompatibleDC(screen); void* bits=nullptr;
  HBITMAP bitmap=CreateDIBSection(screen,&info,DIB_RGB_COLORS,&bits,nullptr,0);
  if (bitmap && bits) {
    std::memcpy(bits,frame.bgra.data(),frame.bgra.size());
    HGDIOBJ previous=SelectObject(memory,bitmap);
    SIZE size{width,height}; POINT source{}; BLENDFUNCTION blend{AC_SRC_OVER,0,255,AC_SRC_ALPHA};
    const bool updated=UpdateLayeredWindow(canvas_,screen,&origin,&size,memory,&source,0,&blend,ULW_ALPHA)!=FALSE;
    if(!updated) {
      SelectObject(memory,previous); DeleteObject(bitmap); DeleteDC(memory); ReleaseDC(nullptr,screen);
      throw std::runtime_error("CAPTURE_NATIVE_PRESENTATION_FAILED");
    }
    SelectObject(memory,previous);
    SetWindowPos(canvas_,HWND_TOP,origin.x,origin.y,width,height,SWP_NOACTIVATE|SWP_SHOWWINDOW|SWP_NOZORDER|SWP_NOOWNERZORDER);
    // Keep only the small native Stop control interactive above presentation.
    SetWindowPos(stop_window_,HWND_TOP,0,0,0,0,SWP_NOMOVE|SWP_NOSIZE|SWP_NOACTIVATE|SWP_NOZORDER|SWP_NOOWNERZORDER);
  }
  if (bitmap) DeleteObject(bitmap);
  DeleteDC(memory); ReleaseDC(nullptr,screen);
}
}
