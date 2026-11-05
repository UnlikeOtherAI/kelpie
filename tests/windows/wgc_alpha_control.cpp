#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#include <windows.h>
#include <cstdint>
#include <cstring>
#include <iostream>
#include <stdexcept>
#include <string_view>

namespace {
constexpr int Width=320,Height=160;
struct Pixel { BYTE b,g,r,a; };
static_assert(sizeof(Pixel)==4);
Pixel ControlPixel(int x) {
  if(x<100) return {0,0,178,178};
  if(x<200) return {0,89,0,89};
  if(x<300) return {255,0,0,255};
  return {0,0,0,0};
}
LRESULT CALLBACK WindowProc(HWND hwnd,UINT msg,WPARAM wp,LPARAM lp) {
  if(msg==WM_TIMER || msg==WM_CLOSE) { DestroyWindow(hwnd); return 0; }
  if(msg==WM_DESTROY) { PostQuitMessage(0); return 0; }
  return DefWindowProcW(hwnd,msg,wp,lp);
}
void Require(bool ok) { if(!ok) throw std::runtime_error("CONTROL_API_FAILED"); }
std::uint64_t StartTime() {
  FILETIME start{},end{},kernel{},user{};
  Require(GetProcessTimes(GetCurrentProcess(),&start,&end,&kernel,&user)!=FALSE);
  return (static_cast<std::uint64_t>(start.dwHighDateTime)<<32)|start.dwLowDateTime;
}
}
int wmain(int argc,wchar_t** argv) {
  try {
    if(argc==2 && std::wstring_view(argv[1])==L"self-test") {
      const auto a=ControlPixel(50),b=ControlPixel(150),c=ControlPixel(250),d=ControlPixel(310);
      Require(a.r==178 && a.a==178 && b.g==89 && b.a==89 && c.b==255 && c.a==255 && d.a==0);
      std::cout<<"CONTROL_SELF_TEST_OK"<<std::endl; return 0;
    }
    Require(argc==1);
    const auto instance=GetModuleHandleW(nullptr);
    WNDCLASSW wc{};wc.lpfnWndProc=WindowProc;wc.hInstance=instance;wc.lpszClassName=L"KelpieScriptPresentation";
    Require(RegisterClassW(&wc)!=0);
    HWND hwnd=CreateWindowExW(WS_EX_LAYERED|WS_EX_TOOLWINDOW|WS_EX_NOACTIVATE,wc.lpszClassName,L"WGC alpha calibration",
      WS_POPUP,20,20,Width,Height,nullptr,nullptr,instance,nullptr);
    Require(hwnd!=nullptr);
    BITMAPINFO info{};info.bmiHeader.biSize=sizeof(BITMAPINFOHEADER);info.bmiHeader.biWidth=Width;
    info.bmiHeader.biHeight=-Height;info.bmiHeader.biPlanes=1;info.bmiHeader.biBitCount=32;info.bmiHeader.biCompression=BI_RGB;
    void* bits=nullptr;
    HDC screen=GetDC(nullptr);Require(screen!=nullptr);
    HDC memory=CreateCompatibleDC(screen);Require(memory!=nullptr);
    HBITMAP bitmap=CreateDIBSection(screen,&info,DIB_RGB_COLORS,&bits,nullptr,0);Require(bitmap && bits);
    auto previous=SelectObject(memory,bitmap);Require(previous!=nullptr && previous!=HGDI_ERROR);
    auto* pixels=static_cast<Pixel*>(bits);
    for(int y=0;y<Height;++y)for(int x=0;x<Width;++x)pixels[y*Width+x]=ControlPixel(x);
    POINT source{0,0},destination{20,20};SIZE size{Width,Height};
    BLENDFUNCTION blend{AC_SRC_OVER,0,255,AC_SRC_ALPHA};
    const bool updated=UpdateLayeredWindow(hwnd,screen,&destination,&size,memory,&source,0,&blend,ULW_ALPHA)!=FALSE;
    SelectObject(memory,previous);DeleteObject(bitmap);DeleteDC(memory);ReleaseDC(nullptr,screen);
    Require(updated);
    Require(SetWindowPos(hwnd,nullptr,0,0,0,0,SWP_NOMOVE|SWP_NOSIZE|SWP_NOZORDER|SWP_NOACTIVATE|SWP_SHOWWINDOW)!=FALSE);
    Require(SetTimer(hwnd,1,15000,nullptr)!=0);
    std::cout<<"{\"pid\":"<<GetCurrentProcessId()<<",\"startFileTime\":\""<<StartTime()
      <<"\",\"hwnd\":\""<<reinterpret_cast<std::uintptr_t>(hwnd)<<"\"}"<<std::endl;
    MSG message{};
    BOOL status=0;
    while((status=GetMessageW(&message,nullptr,0,0))>0) { TranslateMessage(&message);DispatchMessageW(&message); }
    Require(status==0);
    return 0;
  } catch(...) { std::cerr<<"CONTROL_FAILED"<<std::endl;return 1; }
}
