#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>
#include <d3d11.h>
#include <dxgi.h>
#include <windows.graphics.capture.interop.h>
#include <windows.graphics.directx.direct3d11.interop.h>
#include <winrt/Windows.Graphics.Capture.h>
#include <winrt/Windows.Graphics.DirectX.Direct3D11.h>
#include <winrt/Windows.Graphics.Imaging.h>
#include <condition_variable>
#include <mutex>
#include <memory>
#include <iostream>
#include <thread>
#include <atomic>
#include "wgc_capture_files.h"

namespace {
using namespace wgc_test;
using namespace winrt::Windows::Graphics::Capture;
using namespace winrt::Windows::Graphics::Imaging;
struct Owner {
  DWORD pid;std::wstring executable;std::uint64_t creation;HWND window;
  void Verify() const {
    DWORD selfSession=0,targetSession=0,windowPid=0;
    if(!ProcessIdToSessionId(GetCurrentProcessId(),&selfSession)||selfSession!=1||
       !ProcessIdToSessionId(pid,&targetSession)||targetSession!=1)
      throw std::runtime_error("WGC_SESSION_MISMATCH");
    winrt::handle process{OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION,FALSE,pid)};
    if(!process)throw std::runtime_error("WGC_PROCESS_UNAVAILABLE");
    FILETIME began{},exit{},kernel{},user{};DWORD code=0;
    if(!GetProcessTimes(process.get(),&began,&exit,&kernel,&user)||!GetExitCodeProcess(process.get(),&code)||code!=STILL_ACTIVE)
      throw std::runtime_error("WGC_PROCESS_CHANGED");
    const auto actual=(static_cast<std::uint64_t>(began.dwHighDateTime)<<32)|began.dwLowDateTime;
    wchar_t path[4096]{};DWORD length=4096;
    if(actual!=creation||!QueryFullProcessImageNameW(process.get(),0,path,&length)||_wcsicmp(path,executable.c_str())!=0)
      throw std::runtime_error("WGC_PROCESS_IDENTITY_MISMATCH");
    GetWindowThreadProcessId(window,&windowPid);
    wchar_t klass[128]{};
    if(windowPid!=pid||!IsWindowVisible(window)||!GetClassNameW(window,klass,128)||
       std::wstring(klass)!=L"KelpieScriptPresentation")
      throw std::runtime_error("WGC_WINDOW_IDENTITY_MISMATCH");
  }
};
struct State {
  std::mutex mutex;std::condition_variable changed;bool done=false,cancelled=false;
  Direct3D11CaptureFrame frame{nullptr};std::exception_ptr error;
};
struct Capture {
  GraphicsCaptureItem item{nullptr};Direct3D11CaptureFramePool pool{nullptr};
  GraphicsCaptureSession session{nullptr};Direct3D11CaptureFrame frame{nullptr};
  winrt::event_token frameEvent{},closedEvent{};std::shared_ptr<State> state=std::make_shared<State>();
  void Stop() noexcept {
    {std::lock_guard lock(state->mutex);state->cancelled=true;}
    try{if(pool&&frameEvent.value)pool.FrameArrived(frameEvent);}catch(...){}
    frameEvent={};
    try{if(item&&closedEvent.value)item.Closed(closedEvent);}catch(...){}
    closedEvent={};
    try{if(session)session.Close();}catch(...){}
    session=nullptr;
  }
  ~Capture() {
    Stop();
    try{if(frame)frame.Close();}catch(...){}
    frame=nullptr;
    try{if(pool)pool.Close();}catch(...){}
    pool=nullptr;item=nullptr;
    {std::lock_guard lock(state->mutex);try{if(state->frame)state->frame.Close();}catch(...){}state->frame=nullptr;}
  }
};
std::string AlphaName(BitmapAlphaMode mode) {
  if(mode==BitmapAlphaMode::Premultiplied)return "premultiplied";
  if(mode==BitmapAlphaMode::Straight)return "straight";
  if(mode==BitmapAlphaMode::Ignore)return "ignore";
  throw std::runtime_error("WGC_ALPHA_MODE");
}
#include "wgc_bounded_stream.h"
#include "wgc_timeline.h"
Json Run(Owner const& owner,std::filesystem::path const& output) {
  owner.Verify();
  Stage="capture-capability";
  if(!GraphicsCaptureSession::IsSupported())throw std::runtime_error("WGC_UNSUPPORTED");
  if(std::filesystem::exists(output)||!std::filesystem::create_directory(output))
    throw std::runtime_error("WGC_FRESH_DIRECTORY_REQUIRED");
  const auto deadline=Clock::now()+std::chrono::seconds(8);
  auto fence=[owner,deadline]{Deadline(deadline);owner.Verify();};
  winrt::com_ptr<ID3D11Device> device;winrt::com_ptr<ID3D11DeviceContext> context;
  D3D_FEATURE_LEVEL level{};
  Stage="d3d11-device-create";
  Check(D3D11CreateDevice(nullptr,D3D_DRIVER_TYPE_HARDWARE,nullptr,D3D11_CREATE_DEVICE_BGRA_SUPPORT,
    nullptr,0,D3D11_SDK_VERSION,device.put(),&level,context.put()));
  Stage="dxgi-device-query";
  auto dxgi=device.as<IDXGIDevice>();
  winrt::Windows::Foundation::IInspectable inspectable{nullptr};
  Stage="winrt-d3d11-device-create";
  Check(CreateDirect3D11DeviceFromDXGIDevice(dxgi.get(),reinterpret_cast<IInspectable**>(winrt::put_abi(inspectable))));
  Stage="winrt-d3d11-device-query";
  auto projected=inspectable.as<winrt::Windows::Graphics::DirectX::Direct3D11::IDirect3DDevice>();
  Capture capture;
  Stage="capture-item-factory";
  auto factory=winrt::get_activation_factory<GraphicsCaptureItem>();
  Stage="capture-item-interop-query";
  auto interop=factory.as<IGraphicsCaptureItemInterop>();
  fence();
  Stage="capture-item-create-for-owned-window";
  Check(interop->CreateForWindow(owner.window,winrt::guid_of<GraphicsCaptureItem>(),winrt::put_abi(capture.item)));
  Stage="capture-item-size";
  const auto size=capture.item.Size();
  if(size.Width<=0||size.Height<=0||size.Width>4096||size.Height>4096||
     static_cast<std::uint64_t>(size.Width)*size.Height>8388608)
    throw std::runtime_error("WGC_PIXEL_BOUND");
  Stage="free-threaded-frame-pool";
  capture.pool=Direct3D11CaptureFramePool::CreateFreeThreaded(projected,
    winrt::Windows::Graphics::DirectX::DirectXPixelFormat::B8G8R8A8UIntNormalized,2,size);
  Stage="capture-session-create";
  capture.session=capture.pool.CreateCaptureSession(capture.item);
  Stage="cursor-capture-property";
  capture.session.IsCursorCaptureEnabled(false);
  Stage="secondary-windows-property";
  capture.session.IncludeSecondaryWindows(false);
  // Retain the standard OS border. Never request borderless/programmatic
  // consent, open a picker or create a monitor/desktop item.
  Stage="border-required-property";
  if(!capture.session.IsBorderRequired())throw std::runtime_error("WGC_BORDER_REQUIRED");
  auto shared=capture.state;
  capture.frameEvent=capture.pool.FrameArrived([shared](auto const& sender,auto const&){
    try {
      auto frame=sender.TryGetNextFrame();if(!frame)return;
      std::lock_guard lock(shared->mutex);
      if(shared->done||shared->cancelled){frame.Close();return;}
      shared->frame=std::move(frame);shared->done=true;shared->changed.notify_all();
    } catch(...) {
      std::lock_guard lock(shared->mutex);shared->error=std::current_exception();shared->done=true;shared->changed.notify_all();
    }
  });
  capture.closedEvent=capture.item.Closed([shared](auto const&,auto const&){
    std::lock_guard lock(shared->mutex);shared->error=std::make_exception_ptr(std::runtime_error("WGC_ITEM_CLOSED"));
    shared->done=true;shared->changed.notify_all();
  });
  Stage="start-capture";
  capture.session.StartCapture();
  Stage="frame-acquisition";
  {
    std::unique_lock lock(shared->mutex);
    if(!shared->changed.wait_for(lock,std::chrono::seconds(5),[&]{return shared->done;})) {
      shared->cancelled=true;throw std::runtime_error("WGC_FRAME_TIMEOUT");
    }
    if(shared->error)std::rethrow_exception(shared->error);
    capture.frame=std::move(shared->frame);shared->frame=nullptr;
  }
  capture.Stop(); // Border/session ends as soon as this single frame is retained.
  fence();
  const auto content=capture.frame.ContentSize();
  if(content.Width!=size.Width||content.Height!=size.Height)throw std::runtime_error("WGC_SIZE_CHANGED");
  Stage="frame-surface-query";
  const auto surface=capture.frame.Surface();
  Stage="software-bitmap-deep-copy";
  auto bitmap=Wait(SoftwareBitmap::CreateCopyFromSurfaceAsync(surface),deadline);
  if(bitmap.PixelWidth()!=size.Width||bitmap.PixelHeight()!=size.Height||bitmap.BitmapPixelFormat()!=BitmapPixelFormat::Bgra8)
    throw std::runtime_error("WGC_SURFACE_FORMAT_CHANGED");
  Stage="software-bitmap-alpha-property";
  const auto alpha=AlphaName(bitmap.BitmapAlphaMode());
  auto pixels=CopyBytes(bitmap);
  std::uint64_t zero=0,partial=0,opaque=0,nonBlack=0;
  for(std::size_t at=0;at<pixels.size();at+=4) {
    const BYTE a=pixels[at+3];
    if(a==0)++zero;else if(a==255)++opaque;else ++partial;
    if(static_cast<unsigned>(pixels[at])+pixels[at+1]+pixels[at+2]>24)++nonBlack;
    if(alpha=="premultiplied"&&(pixels[at]>a+1||pixels[at+1]>a+1||pixels[at+2]>a+1))
      throw std::runtime_error("WGC_ALPHA_MODE_INCONSISTENT");
  }
  if(alpha=="ignore"&&(zero||partial))throw std::runtime_error("WGC_ALPHA_IGNORED");
  Stage="raw-file-persistence";
  fence();auto raw=RawFile(output/"frame.bgra",pixels,fence);fence();
  Stage="png-file-encoding";
  auto png=PngFile(output/"frame.png",size.Width,size.Height,pixels,alpha,fence);fence();
  Json result={{"method","Windows.Graphics.Capture CreateForWindow; exact presentation HWND"},
    {"processId",owner.pid},{"startFileTime",std::to_string(owner.creation)},
    {"windowHandle",std::to_string(reinterpret_cast<std::uintptr_t>(owner.window))},
    {"className","KelpieScriptPresentation"},{"width",size.Width},{"height",size.Height},{"stride",size.Width*4},
    {"alphaMode",alpha},{"alphaZero",zero},{"alphaPartial",partial},{"alphaOpaque",opaque},{"nonBlackPixels",nonBlack},
    {"raw",raw},{"png",png},{"cursorCapture",false},{"borderRequired",true},{"secondaryWindows",false},
    {"framePoolBuffers",2},{"sessionClosedBeforeEncoding",true},{"frameSystemTime100ns",std::to_string(capture.frame.SystemRelativeTime().count())},
    {"rawSource","SoftwareBitmap deep copy of the native capture surface; API-reported alpha mode"}};
  const auto text=result.dump(2);std::vector<BYTE> metadata(text.begin(),text.end());
  fence();RawFile(output/"metadata.json",metadata,fence);
  bitmap.Close();return result;
}
Json BufferSelfTest() {
  Stage="buffer-self-test";
  SoftwareBitmap bitmap(BitmapPixelFormat::Bgra8,4,3,BitmapAlphaMode::Premultiplied);
  auto write=bitmap.LockBuffer(BitmapBufferAccessMode::ReadWrite);
  auto reference=write.CreateReference();auto plane=write.GetPlaneDescription(0);
  GUID old_iid{};Check(IIDFromString(L"{5B0D3235-4DBA-4D44-8656-1D0E4FD04D4F}",&old_iid));
  void* rejected=nullptr;
  const auto legacy=reference.as<IUnknown>()->QueryInterface(old_iid,&rejected);
  if(rejected)static_cast<IUnknown*>(rejected)->Release();
  if(legacy!=E_NOINTERFACE)throw std::runtime_error("SELF_TEST_LEGACY_IID");
  BYTE* data=nullptr;UINT32 capacity=0;
  Check(reference.as<::Windows::Foundation::IMemoryBufferByteAccess>()->GetBuffer(&data,&capacity));
  if(capacity>65536||plane.StartIndex<0||plane.Stride<16)throw std::runtime_error("SELF_TEST_LAYOUT");
  std::memset(data,0,capacity);
  for(int y=0;y<3;++y)for(int x=0;x<4;++x) {
    auto* pixel=data+plane.StartIndex+y*plane.Stride+x*4;
    if(pixel+4>data+capacity)throw std::runtime_error("SELF_TEST_LAYOUT");
    pixel[0]=9;pixel[1]=17;pixel[2]=50;pixel[3]=80;
  }
  reference.Close();write.Close();
  const auto copy=CopyBytes(bitmap);
  if(copy.size()!=48)throw std::runtime_error("SELF_TEST_COPY_SIZE");
  for(std::size_t at=0;at<copy.size();at+=4)
    if(copy[at]!=9||copy[at+1]!=17||copy[at+2]!=50||copy[at+3]!=80)throw std::runtime_error("SELF_TEST_COPY_BYTES");
  bitmap.Close();
  return {{"selfTest",true},{"pixelsCopied",12},{"legacyWrongIidResult",static_cast<std::int32_t>(legacy)},{"sdkByteAccess",true}};
}
}
int wmain(int argc,wchar_t** argv) {
  try {
    winrt::init_apartment(winrt::apartment_type::multi_threaded);
    if(argc==2&&std::wstring(argv[1])==L"self-test-buffer"){std::cout<<BufferSelfTest().dump()<<std::endl;return 0;}
    if(argc==2&&std::wstring(argv[1])==L"self-test-timeline-stream"){std::cout<<TimelineStreamSelfTest().dump()<<std::endl;return 0;}
    if(argc==2&&std::wstring(argv[1])==L"self-test-timeline-writer"){std::cout<<TimelineWriterSelfTest().dump()<<std::endl;return 0;}
    if(argc==7&&std::wstring(argv[1])==L"timeline"){
      Owner owner{static_cast<DWORD>(std::stoul(argv[2])),argv[3],std::stoull(argv[4]),
        reinterpret_cast<HWND>(static_cast<std::uintptr_t>(std::stoull(argv[5])))};
      (void)RunTimeline(owner,argv[6]);return 0;
    }
    if(argc!=6)throw std::runtime_error("EXPECTED_PID_EXE_STARTFILETIME_HWND_FRESH_OUTPUT");
    Owner owner{static_cast<DWORD>(std::stoul(argv[1])),argv[2],std::stoull(argv[3]),
      reinterpret_cast<HWND>(static_cast<std::uintptr_t>(std::stoull(argv[4])))};
    const auto result=Run(owner,argv[5]);std::cout<<result.dump()<<std::endl;return 0;
  } catch(winrt::hresult_error const& error) {
    std::cerr<<"WGC_API_FAILURE stage="<<Stage<<" "<<static_cast<std::int32_t>(error.code())<<std::endl;return 1;
  } catch(std::exception const& error) {std::cerr<<error.what()<<std::endl;return 1;}
}
