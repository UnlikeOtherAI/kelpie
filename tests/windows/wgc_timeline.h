#pragma once
// Test-only timeline mode. Owner and the WGC aliases are defined by the caller.
struct TimelineState {
  std::mutex mutex;std::condition_variable changed;
  Direct3D11CaptureFrame latest{nullptr};std::uint64_t receipt=0,replaced=0;
  bool cancelled=false,closed=false;std::exception_ptr error;
};
struct TimelineCapture {
  GraphicsCaptureItem item{nullptr};Direct3D11CaptureFramePool pool{nullptr};
  GraphicsCaptureSession session{nullptr};winrt::event_token frameEvent{},closedEvent{};
  std::shared_ptr<TimelineState> state=std::make_shared<TimelineState>();
  std::mutex stopMutex;bool stopped=false;
  void Stop() noexcept {
    std::lock_guard stopLock(stopMutex);if(stopped)return;stopped=true;
    {std::lock_guard lock(state->mutex);state->cancelled=true;state->changed.notify_all();}
    try{if(pool&&frameEvent.value)pool.FrameArrived(frameEvent);}catch(...){}frameEvent={};
    try{if(item&&closedEvent.value)item.Closed(closedEvent);}catch(...){}closedEvent={};
    try{if(session)session.Close();}catch(...){}session=nullptr;
    {std::lock_guard lock(state->mutex);try{if(state->latest)state->latest.Close();}catch(...){}state->latest=nullptr;}
    try{if(pool)pool.Close();}catch(...){}pool=nullptr;item=nullptr;
  }
  ~TimelineCapture(){Stop();}
};
struct TimelineDeadline {
  std::mutex mutex;std::condition_variable changed;bool cancelled=false;std::thread thread;
  TimelineDeadline(TimelineCapture& capture,Clock::time_point deadline):thread([this,&capture,deadline]{
    std::unique_lock lock(mutex);if(!changed.wait_until(lock,deadline,[this]{return cancelled;})){lock.unlock();capture.Stop();}
  }){}
  void Cancel() noexcept {{std::lock_guard lock(mutex);cancelled=true;changed.notify_all();}if(thread.joinable())thread.join();}
  ~TimelineDeadline(){Cancel();}
};
struct TimelinePacket {Json header;std::vector<BYTE> pixels;};
struct TimelineWriter {
  std::mutex mutex;std::condition_variable changed;std::unique_ptr<TimelinePacket> pending;
  std::atomic<bool> cancel{false};bool closing=false,done=false,failed=false;
  std::uint64_t replaced=0,written=0;std::thread thread;
  TimelineWriter():thread([this]{Run();}){}
  bool Write(HANDLE output,const BYTE* data,std::size_t size){
    while(size&&!cancel.load()){
      DWORD count=0,part=static_cast<DWORD>(std::min<std::size_t>(size,65536));
      if(!WriteFile(output,data,part,&count,nullptr)||count==0)return false;
      data+=count;size-=count;
    }
    return size==0;
  }
  void Run() noexcept {
    try{
      const HANDLE output=GetStdHandle(STD_OUTPUT_HANDLE);
      if(output==nullptr||output==INVALID_HANDLE_VALUE)throw std::runtime_error("WGC_STREAM_UNAVAILABLE");
      for(;;){
        std::unique_ptr<TimelinePacket> packet;
        {std::unique_lock lock(mutex);changed.wait(lock,[this]{return closing||pending;});
         if(!pending&&closing)break;packet=std::move(pending);}
        packet->header["sequence"]=written;const auto text=packet->header.dump();
        if(text.empty()||text.size()>4096||packet->pixels.size()>4096000)throw std::runtime_error("WGC_STREAM_BOUND");
        const std::uint32_t sizes[2]={static_cast<std::uint32_t>(text.size()),static_cast<std::uint32_t>(packet->pixels.size())};
        if(!Write(output,reinterpret_cast<const BYTE*>(sizes),sizeof(sizes))||
           !Write(output,reinterpret_cast<const BYTE*>(text.data()),text.size())||
           !Write(output,packet->pixels.data(),packet->pixels.size()))throw std::runtime_error("WGC_STREAM_WRITE");
        ++written;
      }
    }catch(...){std::lock_guard lock(mutex);failed=true;}
    {std::lock_guard lock(mutex);done=true;changed.notify_all();}
  }
  void Offer(std::unique_ptr<TimelinePacket> packet){
    std::lock_guard lock(mutex);if(closing||failed)throw std::runtime_error("WGC_STREAM_STOPPED");
    if(pending)++replaced;pending=std::move(packet);changed.notify_one();
  }
  void Stop() noexcept {
    {std::lock_guard lock(mutex);closing=true;changed.notify_all();}
    if(!thread.joinable())return;
    {std::unique_lock lock(mutex);changed.wait_for(lock,std::chrono::seconds(2),[this]{return done;});}
    {std::lock_guard lock(mutex);if(!done)cancel.store(true);}
    for(int attempt=0;attempt<20;++attempt){
      {std::lock_guard lock(mutex);if(done)break;}
      CancelSynchronousIo(thread.native_handle());std::this_thread::sleep_for(std::chrono::milliseconds(10));
    }
    thread.join();
  }
  ~TimelineWriter(){Stop();}
};
inline Json TimelineWriterSelfTest(){
  HANDLE readRaw=nullptr,writeRaw=nullptr;if(!CreatePipe(&readRaw,&writeRaw,nullptr,4096))throw std::runtime_error("WGC_SELFTEST_PIPE");
  winrt::handle input{readRaw},output{writeRaw};const HANDLE previous=GetStdHandle(STD_OUTPUT_HANDLE);
  struct Restore {HANDLE handle;~Restore(){SetStdHandle(STD_OUTPUT_HANDLE,handle);}} restore{previous};
  if(!SetStdHandle(STD_OUTPUT_HANDLE,output.get()))throw std::runtime_error("WGC_SELFTEST_PIPE");
  TimelineWriter writer;auto packet=[] {auto p=std::make_unique<TimelinePacket>();p->header={{"tick100ns",1}};p->pixels.resize(2097152,0);return p;};
  writer.Offer(packet());std::this_thread::sleep_for(std::chrono::milliseconds(100));
  writer.Offer(packet());writer.Offer(packet());
  const auto began=Clock::now();writer.Stop();
  const auto elapsed=std::chrono::duration_cast<std::chrono::milliseconds>(Clock::now()-began).count();
  if(!writer.done||!writer.failed||writer.replaced<1||elapsed>4000)throw std::runtime_error("WGC_SELFTEST_WRITER");
  return {{"boundedWriter",true},{"replacements",writer.replaced},{"elapsedMs",elapsed}};
}
struct TimelineSnapshot {std::vector<BYTE> pixels;std::uint64_t tick=0;};
Json RunTimeline(Owner const& owner,std::filesystem::path const& output){
  winrt::handle memoryJob{CreateJobObjectW(nullptr,nullptr)};
  if(!memoryJob)throw std::runtime_error("WGC_MEMORY_JOB_UNAVAILABLE");
  JOBOBJECT_EXTENDED_LIMIT_INFORMATION memoryLimit{};
  memoryLimit.BasicLimitInformation.LimitFlags=JOB_OBJECT_LIMIT_PROCESS_MEMORY;
  memoryLimit.ProcessMemoryLimit=128ULL*1024*1024;
  if(!SetInformationJobObject(memoryJob.get(),JobObjectExtendedLimitInformation,&memoryLimit,sizeof(memoryLimit))||
     !AssignProcessToJobObject(memoryJob.get(),GetCurrentProcess()))throw std::runtime_error("WGC_MEMORY_JOB_UNAVAILABLE");
  owner.Verify();
  if(!GraphicsCaptureSession::IsSupported())throw std::runtime_error("WGC_UNSUPPORTED");
  if(std::filesystem::exists(output)||!std::filesystem::create_directory(output))throw std::runtime_error("WGC_FRESH_DIRECTORY_REQUIRED");
  const auto began=Clock::now(),captureEnd=began+std::chrono::seconds(26),teardownEnd=began+std::chrono::seconds(35);
  auto captureFence=[owner,captureEnd]{Deadline(captureEnd);owner.Verify();};
  auto teardownFence=[teardownEnd]{Deadline(teardownEnd);};
  winrt::com_ptr<ID3D11Device> device;winrt::com_ptr<ID3D11DeviceContext> context;D3D_FEATURE_LEVEL level{};
  Check(D3D11CreateDevice(nullptr,D3D_DRIVER_TYPE_HARDWARE,nullptr,D3D11_CREATE_DEVICE_BGRA_SUPPORT,nullptr,0,D3D11_SDK_VERSION,device.put(),&level,context.put()));
  auto dxgi=device.as<IDXGIDevice>();winrt::Windows::Foundation::IInspectable inspectable{nullptr};
  Check(CreateDirect3D11DeviceFromDXGIDevice(dxgi.get(),reinterpret_cast<IInspectable**>(winrt::put_abi(inspectable))));
  auto projected=inspectable.as<winrt::Windows::Graphics::DirectX::Direct3D11::IDirect3DDevice>();
  TimelineWriter writer;TimelineCapture capture;auto factory=winrt::get_activation_factory<GraphicsCaptureItem>();
  auto interop=factory.as<IGraphicsCaptureItemInterop>();captureFence();
  Check(interop->CreateForWindow(owner.window,winrt::guid_of<GraphicsCaptureItem>(),winrt::put_abi(capture.item)));
  const auto size=capture.item.Size();
  if(size.Width<=0||size.Height<=0||size.Width>4096||size.Height>4096||
     static_cast<std::uint64_t>(size.Width)*size.Height>2097152)throw std::runtime_error("WGC_TIMELINE_PIXEL_BOUND");
  const int width=std::min(640,size.Width);
  const int height=static_cast<int>((static_cast<std::int64_t>(size.Height)*width+size.Width/2)/size.Width);
  if(height<=0||height>1600)throw std::runtime_error("WGC_ANALYSIS_SIZE");
  capture.pool=Direct3D11CaptureFramePool::CreateFreeThreaded(projected,winrt::Windows::Graphics::DirectX::DirectXPixelFormat::B8G8R8A8UIntNormalized,2,size);
  capture.session=capture.pool.CreateCaptureSession(capture.item);capture.session.IsCursorCaptureEnabled(false);
  capture.session.IncludeSecondaryWindows(false);if(!capture.session.IsBorderRequired())throw std::runtime_error("WGC_BORDER_REQUIRED");
  auto state=capture.state;
  capture.frameEvent=capture.pool.FrameArrived([state](auto const& sender,auto const&){
    try{auto frame=sender.TryGetNextFrame();if(!frame)return;
      std::lock_guard lock(state->mutex);if(state->cancelled){frame.Close();return;}
      if(state->latest){state->latest.Close();++state->replaced;}
      state->latest=std::move(frame);state->receipt=GetTickCount64();state->changed.notify_one();
    }catch(...){std::lock_guard lock(state->mutex);if(!state->cancelled){state->error=std::current_exception();state->changed.notify_one();}}
  });
  capture.closedEvent=capture.item.Closed([state](auto const&,auto const&){std::lock_guard lock(state->mutex);if(!state->cancelled){state->closed=true;state->changed.notify_one();}});
  std::vector<TimelineSnapshot> snapshots;std::string alpha;std::uint64_t lastTick=0,accepted=0,rateSkipped=0;int nextSnapshot=0;
  const double sampleTimes[3]={5.0,13.0,21.0};captureFence();const auto sessionBegan=Clock::now();capture.session.StartCapture();TimelineDeadline deadlineGuard(capture,captureEnd);
  while(Clock::now()<captureEnd&&accepted<520){
    Direct3D11CaptureFrame frame{nullptr};std::uint64_t receipt=0;
    {std::unique_lock lock(state->mutex);state->changed.wait_until(lock,captureEnd,[&]{return state->latest||state->error||state->closed;});
     if(state->error)std::rethrow_exception(state->error);if(state->closed){if(state->latest)state->latest.Close();state->latest=nullptr;break;}
     if(!state->latest)break;frame=std::move(state->latest);state->latest=nullptr;receipt=state->receipt;}
    captureFence();const auto content=frame.ContentSize();
    if(content.Width!=size.Width||content.Height!=size.Height)throw std::runtime_error("WGC_SIZE_CHANGED");
    const auto signedTick=frame.SystemRelativeTime().count();if(signedTick<=0)throw std::runtime_error("WGC_CLOCK");
    const auto tick=static_cast<std::uint64_t>(signedTick);
    if(tick<=lastTick){frame.Close();throw std::runtime_error("WGC_CLOCK");}
    if(lastTick&&tick-lastTick<500000){++rateSkipped;frame.Close();continue;}lastTick=tick;
    auto bitmap=Wait(SoftwareBitmap::CreateCopyFromSurfaceAsync(frame.Surface()),captureEnd);frame.Close();
    if(bitmap.PixelWidth()!=size.Width||bitmap.PixelHeight()!=size.Height||bitmap.BitmapPixelFormat()!=BitmapPixelFormat::Bgra8)throw std::runtime_error("WGC_SURFACE_FORMAT_CHANGED");
    const auto currentAlpha=AlphaName(bitmap.BitmapAlphaMode());if(currentAlpha!="straight"&&currentAlpha!="premultiplied")throw std::runtime_error("WGC_ALPHA_MODE");
    if(alpha.empty())alpha=currentAlpha;else if(alpha!=currentAlpha)throw std::runtime_error("WGC_ALPHA_MODE_CHANGED");
    auto pixels=CopyBytes(bitmap);bitmap.Close();captureFence(); // Only this verified buffer is sealed.
    if(alpha=="premultiplied")for(std::size_t at=0;at<pixels.size();at+=4){
      const int a=pixels[at+3];
      if(pixels[at]>a+1||pixels[at+1]>a+1||pixels[at+2]>a+1)throw std::runtime_error("WGC_ALPHA_MODE_INCONSISTENT");
    }
    auto packet=std::make_unique<TimelinePacket>();packet->pixels.resize(static_cast<std::size_t>(width)*height*4);
    for(int y=0;y<height;++y)for(int x=0;x<width;++x){
      const auto sx=static_cast<int>(static_cast<std::int64_t>(x)*size.Width/width);
      const auto sy=static_cast<int>(static_cast<std::int64_t>(y)*size.Height/height);
      std::memcpy(packet->pixels.data()+(static_cast<std::size_t>(y)*width+x)*4,
                  pixels.data()+(static_cast<std::size_t>(sy)*size.Width+sx)*4,4);
    }
    packet->header={{"tick100ns",tick},{"receiptMs",receipt},{"width",width},{"height",height},
      {"sourceWidth",size.Width},{"sourceHeight",size.Height},{"sourceStride",size.Width*4},{"alphaMode",alpha}};
    writer.Offer(std::move(packet));++accepted;
    const auto elapsed=std::chrono::duration<double>(Clock::now()-began).count();
    if(nextSnapshot<3&&elapsed>=sampleTimes[nextSnapshot]){snapshots.push_back({std::move(pixels),tick});++nextSnapshot;}
  }
  bool naturalClosure=false;{std::lock_guard lock(state->mutex);naturalClosure=state->closed;}
  const std::string endReason=naturalClosure?"item-closed":accepted>=520?"frame-limit":"capture-deadline";
  capture.Stop();const auto sessionEnded=Clock::now();deadlineGuard.Cancel();writer.Stop();teardownFence();
  const auto sessionMs=std::chrono::duration_cast<std::chrono::milliseconds>(sessionEnded-sessionBegan).count();
  if(sessionMs>26000)throw std::runtime_error("WGC_SESSION_DURATION_BOUND");
  if(writer.failed)throw std::runtime_error("WGC_STREAM_FAILED");
  Json saved=Json::array();std::uint64_t persisted=0;
  for(std::size_t index=0;index<snapshots.size();++index){
    teardownFence();const auto stem="sample-"+std::to_string(index);
    const auto rawBytes=snapshots[index].pixels.size();
    if(persisted+rawBytes+4096>=67043328)throw std::runtime_error("WGC_OUTPUT_BOUND");
    auto raw=RawFile(output/(stem+".bgra"),snapshots[index].pixels,teardownFence);
    const auto pngLimit=67043328-persisted-rawBytes-4096;
    auto png=TimelinePngFile(output/(stem+".png"),size.Width,size.Height,snapshots[index].pixels,alpha,teardownFence,pngLimit);
    persisted+=rawBytes+png["byteLength"].get<std::uint64_t>();
    if(persisted>67043328)throw std::runtime_error("WGC_OUTPUT_BOUND");
    saved.push_back({{"tick100ns",snapshots[index].tick},{"raw",raw},{"png",png}});
  }
  Json summary={{"processId",owner.pid},{"startFileTime",std::to_string(owner.creation)},{"windowHandle",std::to_string(reinterpret_cast<std::uintptr_t>(owner.window))},{"className","KelpieScriptPresentation"},{"accepted",accepted},{"written",writer.written},{"writerReplaced",writer.replaced},
    {"poolReplaced",state->replaced},{"rateSkipped",rateSkipped},{"width",size.Width},{"height",size.Height},{"analysisWidth",width},
    {"analysisHeight",height},{"alphaMode",alpha},{"snapshots",saved},{"naturalItemClosure",naturalClosure},{"endReason",endReason},{"sessionDurationMs",sessionMs},{"cursorCapture",false},{"secondaryWindows",false},{"borderRequired",true},{"framePoolBuffers",2},{"memoryLimitBytes",134217728},{"sessionClosedBeforeEncoding",true}};
  const auto text=summary.dump(2);if(text.size()>4096)throw std::runtime_error("WGC_OUTPUT_BOUND");std::vector<BYTE> bytes(text.begin(),text.end());RawFile(output/"summary.json",bytes,teardownFence);
  return summary;
}
